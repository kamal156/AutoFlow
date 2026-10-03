' Keeps WSL Ubuntu (and with it the Windmill containers) running.
' WSL stops a distro ~20 s after the last wsl.exe session attached to it exits,
' which takes Windmill down with it. This starts one hidden, long-lived session.
' flock makes it idempotent: if a keep-alive already holds the lock, the new one
' exits at once, so clicking the icon repeatedly never piles up processes.
' It lasts until Windows logs off or `wsl --shutdown`; open-windmill.bat restarts it.
CreateObject("WScript.Shell").Run _
    "wsl.exe -d Ubuntu -u root -e flock -n /run/windmill-keepalive.lock sleep infinity", 0, False
