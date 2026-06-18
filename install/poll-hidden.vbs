' Start PluribusAI poll daemon only if not already running.
Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")
dir = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.pluribusai\"
pidF = dir & "poll.pid"
If fso.FileExists(pidF) Then
  Set f = fso.OpenTextFile(pidF, 1)
  pid = Trim(f.ReadAll())
  f.Close
  On Error Resume Next
  Set proc = GetObject("winmgmts:").ExecQuery("SELECT * FROM Win32_Process WHERE ProcessId=" & pid)
  If proc.Count > 0 Then
    WScript.Quit 0
  End If
  On Error GoTo 0
End If
ps1 = dir & "poll.ps1"
sh.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """", 0, False