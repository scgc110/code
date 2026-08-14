' start-hidden.vbs — 静默启动 dsh-client（无任何窗口闪现）
Dim fso, folder, ps
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
ps = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File """ & folder & "\client.ps1"""
CreateObject("WScript.Shell").Run ps, 0, False