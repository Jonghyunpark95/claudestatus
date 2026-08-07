' 콘솔 창을 한 번도 띄우지 않고 데스크톱 펫을 실행한다.
' 더블클릭하거나, 로그인 시 자동 실행하려면 이 파일의 바로가기를
' 시작프로그램 폴더(Win+R -> shell:startup)에 넣으면 된다.

Dim shell, here
Set shell = CreateObject("WScript.Shell")
here = CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName)

shell.Run "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & here & "\pet.ps1""", 0, False
