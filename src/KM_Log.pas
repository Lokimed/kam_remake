unit KM_Log;
{$I KaM_Remake.inc}
interface
uses
  SysUtils, Classes, KM_Utils, Log4d, Forms,
  {$IFDEF LINUX}
    SyncObjs
  {$ELSE}
    Windows
  {$ENDIF};

const
  LOG_NET_CATEGORY = 'net';
  LOG_DELIVERY_CATEGORY = 'delivery';

  NO_TIME_LOG_LVL_NAME = 'NoTime';
  ASSERT_LOG_LVL_NAME = 'Assert';

  // Get Logger for specified class and optional category
  function GetLogger(aClass: TClass; aCategory: string = ''): TLogLogger;
  // Get NET category Logger for specified class
  function GetNetLogger(aClass: TClass): TLogLogger;
  // Get DELIVERY category Logger for specified class
  function GetDeliveryLogger(aClass: TClass): TLogLogger;

  // Get executable file directory
  function GetExeDir: string;

type
  TKMLogInitializer = class
    private
      fLogPath: UnicodeString;
      fFileName: UnicodeString;
      fFileNamePrefix: UnicodeString;
      fPathToLogsDir: UnicodeString;
      fInitialized: Boolean;
    public
      constructor Create;
      procedure InitWPrefix(const aFileNamePrefix: UnicodeString);
      procedure InitWName(const aFileName: UnicodeString);
      procedure Init(const aLogPath: UnicodeString);
      procedure DeleteOldLogs;
      property LogPath: UnicodeString read fLogPath;
      property FileNamePrefix: UnicodeString read fFileNamePrefix;
      property PathToLogsDir: UnicodeString read fPathToLogsDir;
      property FileName: UnicodeString read fFileName;
      property IsInitialized: Boolean read fInitialized;
  end;

//  Log file appender
//   	possible options:
//			pathToLogsDir 	- Path to logs dir. Example: C:\Temp
//			fileNamePrefix 	- File name prefix for log file. Suffix for file name is date-time in format yyyy-mm-dd_hh-nn-ss-zzz and .log extension
//			fileName		- File name.
//			layout			- Layout to format logging messages
//
//	Option pathToLogsDir should be set BEFORE any of the options fileName or fileNamePrefix. Otherwise it will be ignored.
//
//	If pathToLogsDir is not set, then Logs dir will be set to ExeDir\Logs, where ExeDir is the directory of executable file
//
//	If both options fileNamePrefix and fileName are setted, then only first will be used.
  TKMLogFileAppender = class(TLogCustomAppender)
  private
    fl: textfile;
    fLogPath: UnicodeString;
    procedure InternalInit;
  protected
    procedure DoAppend(const Message: string); override;
    procedure SetOption(const Name, Value: string); override;
  public
    constructor Create(const aName, aFileName, aFileNamePrefix, aPathToLogsDir: string; const aLayout: ILogLayout = nil); reintroduce; virtual;
    procedure InitLogFileWPrefix(const aFileNamePrefix: string); virtual;
    procedure InitLogFileWName(const aFileName: string); virtual;
  end;

  // Layot to write log messages
  TKMLogLayout = class(TLogCustomLayout)
  private
    fFirstTick: Cardinal;
    fPreviousTick: Cardinal;
    fPreviousDate: TDateTime;
  protected
    function GetHeader: string; override;
    procedure SetOption(const Name, Value: string); override;
  public
    procedure Init; override;
    function Format(const Event: TLogEvent): string; override;
  end;

  // Special log level to write log without time
  TKMInfoNoTimeLogLevel = class(TLogLevel)
  public
    constructor Create;
  end;

  // Special log level to write Assert error messages
  TKMWarnAssertLogLevel = class(TLogLevel)
  public
    constructor Create;
  end;

var
  NoTimeLogLvl: TLogLevel;
  AssertLogLvl: TLogLevel;
  gLogInitializer: TKMLogInitializer;   // log system initializer


implementation
uses
  KM_Defaults;

const
  FileNamePrefixOpt = 'fileNamePrefix';
  PathToLogsDirOpt = 'pathToLogsDir';

//New thread, in which old logs are deleted (used internally)
type
  TKMOldLogsDeleter = class(TThread)
  private
    fPathToLogs: UnicodeString;
  public
    constructor Create(const aPathToLogs: UnicodeString);
    procedure Execute; override;
  end;


{ TKMOldLogsDeleter }
constructor TKMOldLogsDeleter.Create(const aPathToLogs: UnicodeString);
begin
  //Thread isn't started until all constructors have run to completion
  //so Create(False) may be put in front as well
  inherited Create(False);

  //Must set these values BEFORE starting the thread
  FreeOnTerminate := True; //object can be automatically removed after its termination
  fPathToLogs := aPathToLogs;
end;


procedure TKMOldLogsDeleter.Execute;
var
  SearchRec: TSearchRec;
  fileDateTime: TDateTime;
  SearchPattern: string;
begin
  if not DirectoryExists(fPathToLogs) then Exit;

  if not gLogInitializer.FileNamePrefix.IsEmpty then
    SearchPattern := gLogInitializer.FileNamePrefix + '*.log'
  else
    SearchPattern := gLogInitializer.FileName;

  if FindFirst(fPathToLogs + gLogInitializer.FileNamePrefix + '*.log', faAnyFile - faDirectory, SearchRec) = 0 then
  repeat
    Assert(FileAge(fPathToLogs + SearchRec.Name, fileDateTime), 'How is that it does not exists any more?');

    if (Abs(Now - fileDateTime) > DEL_LOGS_OLDER_THAN) then
      SysUtils.DeleteFile(fPathToLogs + SearchRec.Name);
  until (FindNext(SearchRec) <> 0);
  SysUtils.FindClose(SearchRec);
end;


{TKMLogInitializer}
constructor TKMLogInitializer.Create;
begin
  inherited Create;
  fInitialized := False;
end;


// Logs initialization with FileNamePrefix
procedure TKMLogInitializer.InitWPrefix(const aFileNamePrefix: UnicodeString);
var PathToLogsDir: string;
begin
  if fInitialized then Exit;  // Logs are initialized only once;
  Assert(not aFileNamePrefix.IsEmpty(), 'Error: empty parameter "' + FileNamePrefixOpt + '" of TKMLogFileAppender');
  fFileNamePrefix := aFileNamePrefix;
  InitWName(aFileNamePrefix + FormatDateTime('yyyy-mm-dd_hh-nn-ss-zzz', Now) + '.log');
end;


// Logs initialization with FileNamePrefix
procedure TKMLogInitializer.InitWName(const aFileName: UnicodeString);
begin
  if fInitialized then Exit;  // Logs are initialized only once;
  Assert(not aFileName.IsEmpty(), 'Error: fileName is empty for TKMLogFileAppender');
  // Check if fPathToLogsDir is Set. If not - use default value
  if fPathToLogsDir.IsEmpty then
    fPathToLogsDir := GetExeDir + 'Logs';   // Default dir for Logs
  Init(fPathToLogsDir + PathDelim + aFileName);
end;


//Logs initialization with full path to log file
procedure TKMLogInitializer.Init(const aLogPath: UnicodeString);
begin
  if fInitialized then Exit;  // Logs are initialized only once;
  fLogPath := aLogPath;
  fInitialized := True;
end;


procedure TKMLogInitializer.DeleteOldLogs;
begin
  if not fInitialized then Exit;
  TKMOldLogsDeleter.Create(PathToLogsDir);
end;


{TKMLogFileAppender}
constructor TKMLogFileAppender.Create(const aName, aFileName, aFileNamePrefix, aPathToLogsDir: string; const aLayout: ILogLayout = nil);
begin
  inherited Create(aName, aLayout);
  SetOption(PathToLogsDirOpt, aPathToLogsDir);
  SetOption(FileNamePrefixOpt, aFileNamePrefix);
  SetOption(FileNameOpt, aFileName);
end;

// parse appender options
procedure TKMLogFileAppender.SetOption(const Name: string; const Value: string);
begin
  inherited SetOption(Name, Value);
  EnterCriticalSection(FCriticalAppender);
  try
    if (Value <> '') then
    begin
      if (Name = PathToLogsDirOpt) then
        gLogInitializer.fPathToLogsDir := Value
      else if (Name = FileNamePrefixOpt) then
        InitLogFileWPrefix(Value)
      else if (Name = FileNameOpt) then
        InitLogFileWName(Value);
    end;
  finally
    LeaveCriticalSection(FCriticalAppender);
  end;
end;

//Init appender with filename prefix
procedure TKMLogFileAppender.InitLogFileWPrefix(const aFileNamePrefix: UnicodeString);
var
  strPath: string;
  f : TextFile;
begin
  if gLogInitializer.IsInitialized then Exit;

  gLogInitializer.InitWPrefix(aFileNamePrefix); // Init log system with file name prefix
  InternalInit;
end;

//Init appender with filename
procedure TKMLogFileAppender.InitLogFileWName(const aFileName: UnicodeString);
var
  strPath: string;
  f : TextFile;
begin
  if gLogInitializer.IsInitialized then Exit;

  gLogInitializer.InitWName(aFileName);   // Init log system with file name
  InternalInit;
end;


procedure TKMLogFileAppender.InternalInit;
begin
  fLogPath := gLogInitializer.LogPath;
  ForceDirectories(gLogInitializer.PathToLogsDir);
  AssignFile(fl, fLogPath);
  Rewrite(fl);
  CloseFile(fl);
  DoAppend('Log is up and running. Game version: ' + GAME_VERSION + sLineBreak);
end;


procedure TKMLogFileAppender.DoAppend(const Message: string);
begin
  AssignFile(fl, fLogPath);
  System.Append(fl);
  Write(fl, Message);
  // Close file every time we write in it to avoid any loss of log messages
  CloseFile(fl);
end;


{TKMLogLayout}
procedure TKMLogLayout.Init;
begin
  fFirstTick := TimeGet;
  fPreviousTick := TimeGet;
end;


function TKMLogLayout.GetHeader: string;
begin
  Result := '   Timestamp    Elapsed     Delta    Category                    Level    Description' + sLineBreak;
end;


procedure TKMLogLayout.SetOption(const Name, Value: string);
begin
  // To prevent errors in Log4d
end;


function TKMLogLayout.Format(const Event: TLogEvent): string;
begin
  Result := '';
  //Write a line when the day changed since last time (useful for dedicated server logs that could be over months)
  if Abs(Trunc(fPreviousDate) - Trunc(Now)) >= 1 then
  begin
    Result := Result + '========================' + sLineBreak;
    Result := Result + '    Date: ' + FormatDateTime('yyyy/mm/dd', Now) + sLineBreak;
    Result := Result + '========================' + sLineBreak;
  end;

  if (Event.Level.Name = NO_TIME_LOG_LVL_NAME) then
  begin
    Result := Result +
      '                                                                          ' +
      Event.Message + sLineBreak;
  end else if (Event.Level.Name = ASSERT_LOG_LVL_NAME) then
  begin
    Result := Result +
      '                                                                 warn    ASSERTION FAILED! Msg: ' +
      Event.Message + sLineBreak;
    Assert(False, 'ASSERTION FAILED! Msg: ' + Event.Message);
  end else begin
    Result := Result +
      SysUtils.Format('%12s %9.3fs %7dms    %-27s %-8s %s', [
      FormatDateTime('hh:nn:ss.zzz', Now),
      GetTimeSince(fFirstTick) / 1000,
      GetTimeSince(fPreviousTick),
      Event.LoggerName,
      Event.Level.Name,
      Event.Message]) + sLineBreak;
  end;

  fPreviousTick := TimeGet;
  fPreviousDate := Now;
end;


{TKMInfoNoTimeLogLevel}
constructor TKMInfoNoTimeLogLevel.Create;
begin
  inherited Create(NO_TIME_LOG_LVL_NAME, InfoValue + 100);
end;


{TKMWarnAssertLogLevel}
constructor TKMWarnAssertLogLevel.Create;
begin
  inherited Create(ASSERT_LOG_LVL_NAME, WarnValue + 100);
end;


{log static functions}
function GetLogger(aClass: TClass; aCategory: string = ''): TLogLogger;
begin
  if (aCategory <> '') then
    Result := TLogLogger.GetLogger(aCategory + '.' + aClass.ClassName)
  else
    Result := TLogLogger.GetLogger(aClass.ClassName);
end;


function GetNetLogger(aClass: TClass): TLogLogger;
begin
  Result := GetLogger(aClass, LOG_NET_CATEGORY);
end;


function GetDeliveryLogger(aClass: TClass): TLogLogger;
begin
  Result := GetLogger(aClass, LOG_DELIVERY_CATEGORY);
end;


function GetExeDir: string;
begin
  if (ExeDir.IsEmpty) then
    ExeDir := ExtractFilePath(Application.ExeName);
  Result := ExeDir;
end;


initialization
  // Register Custom Logger classes
  RegisterLayout(TKMLogLayout);
  RegisterAppender(TKMLogFileAppender);

  NoTimeLogLvl := TKMInfoNoTimeLogLevel.Create;
  AssertLogLvl := TKMWarnAssertLogLevel.Create;

end.
