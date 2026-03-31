unit ThreadTimerComp;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs;

type
  TThreadTimerComp = class; // 전방 선언

  // 1. 백그라운드에서 실제로 돌아갈 내부 스레드
  TInternalTimerThread = class(TThread)
  private
    FOwner: TThreadTimerComp;
    FEvent: TEvent;
  protected
    procedure Execute; override;
  public
    constructor Create(AOwner: TThreadTimerComp);
    destructor Destroy; override;
    procedure WakeUp;
  end;

  // 2. 툴 팔레트에 등록될 컴포넌트 본체
  TThreadTimerComp = class(TComponent)
  private
    FThread: TInternalTimerThread;
    FEnabled: Boolean;
    FInterval: Cardinal;
    FOnTimer: TNotifyEvent;
    procedure SetEnabled(const Value: Boolean);
    procedure SetInterval(const Value: Cardinal);
  protected
    procedure DoTimer;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    // Object Inspector(속성창)에 노출될 프로퍼티들 (Published 섹션 필수)
    property Enabled: Boolean read FEnabled write SetEnabled default False;
    property Interval: Cardinal read FInterval write SetInterval default 1000;
    property OnTimer: TNotifyEvent read FOnTimer write FOnTimer;
  end;

// 델파이 IDE에 컴포넌트를 등록하는 필수 프로시저
procedure Register;

implementation

procedure Register;
begin
  // Tool Palette의 'Custom' 이라는 카테고리에 등록합니다.
  RegisterComponents('Custom', [TThreadTimerComp]);
end;

{ TInternalTimerThread }

constructor TInternalTimerThread.Create(AOwner: TThreadTimerComp);
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FOwner := AOwner;
  FEvent := TEvent.Create(nil, False, False, '');
end;

destructor TInternalTimerThread.Destroy;
begin
  Terminate;
  FEvent.SetEvent;
  WaitFor;
  FEvent.Free;
  inherited Destroy;
end;

procedure TInternalTimerThread.WakeUp;
begin
  FEvent.SetEvent;
end;

procedure TInternalTimerThread.Execute;
var
  WaitRes: TWaitResult;
begin
  while not Terminated do
  begin
    // 델파이 폼 디자인 중(디자인 타임)일 때는 타이머가 작동하지 않도록 보호합니다.
    if (csDesigning in FOwner.ComponentState) then
    begin
      FEvent.WaitFor(INFINITE);
      Continue;
    end;

    if FOwner.FEnabled then
    begin
      WaitRes := FEvent.WaitFor(FOwner.FInterval);
      
      if Terminated then Break;

      if WaitRes = wrTimeout then
      begin
        Synchronize(FOwner.DoTimer);
      end;
    end
    else
    begin
      FEvent.WaitFor(INFINITE); // Enabled가 False면 무한 대기
    end;
  end;
end;

{ TThreadTimerComp }

constructor TThreadTimerComp.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FEnabled := False;
  FInterval := 1000;
  
  // 컴포넌트 생성 시 내부 스레드도 함께 생성합니다.
  FThread := TInternalTimerThread.Create(Self);
end;

destructor TThreadTimerComp.Destroy;
begin
  // 내부 스레드를 먼저 안전하게 종료 및 해제합니다.
  FThread.Free;
  inherited Destroy;
end;

procedure TThreadTimerComp.SetEnabled(const Value: Boolean);
begin
  if FEnabled <> Value then
  begin
    FEnabled := Value;
    if Assigned(FThread) then
      FThread.WakeUp; // 상태가 바뀌면 스레드를 깨워 상황을 알립니다.
  end;
end;

procedure TThreadTimerComp.SetInterval(const Value: Cardinal);
begin
  if FInterval <> Value then
  begin
    FInterval := Value;
    if FEnabled and Assigned(FThread) then
      FThread.WakeUp;
  end;
end;

procedure TThreadTimerComp.DoTimer;
begin
  if Assigned(FOnTimer) and FEnabled then
    FOnTimer(Self);
end;

end.