KKS Explorer for your own computer
==================================

WINDOWS
1. Unzip the whole file first (right-click → Extract All). It does not run from inside the zip.
2. Open the folder "KKS Explorer" and double-click "KKS Explorer.exe". You can make a shortcut to it on the desktop.
3. The first time, Windows may show "Windows protected your PC": click "More info", then "Run anyway".
   (The program is not signed with a paid certificate; that is all this warning means.)
4. Windows Firewall asks whether to allow it: tick "Private networks" (needed to sync with colleagues on the same
   Wi-Fi). "Public networks" is not needed.

LINUX
1. Unpack: tar -xzf KKS-Explorer-linux.tar.gz
2. ./install-linux.sh puts it in your applications menu (or run "KKS Explorer/KKS Explorer" directly).

USING IT
- It opens in your web browser and shows a small window with Open / Quit. Closing that window stops it.
- First start: join the plant (through the plant server with your account, or with a join file an admin certifies).
- Your data stays in your user folder, not in the program folder:
    Windows  %APPDATA%\KKS Explorer          Linux  ~/.local/share/kks-explorer
  A new version: replace the program folder (or run install-linux.sh again). Your data is kept.
- Problems: the log is kks-explorer.log in that same data folder.
