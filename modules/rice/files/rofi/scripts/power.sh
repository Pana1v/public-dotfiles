#!/usr/bin/env bash
# Rofi script mode: lock, suspend, log out, reboot, shut down.
# Log out, reboot and shut down show a confirm row first, so one stray Enter can't.

# row <text> <icon> <action>: rofi hands <action> back in ROFI_INFO when picked
row() { printf '%s\0icon\x1f%s\x1finfo\x1f%s\n' "$1" "$2" "$3"; }

menu() {
    printf '\0no-custom\x1ftrue\n'
    printf '\0message\x1f%s\n' "$(uptime -p)"
    row "Lock"      system-lock-screen-symbolic lock
    row "Suspend"   system-suspend-symbolic     suspend
    row "Log out"   system-log-out-symbolic     logout
    row "Reboot"    system-reboot-symbolic      reboot
    row "Shut down" system-shutdown-symbolic    poweroff
}

# confirm <label> <icon> <action>
confirm() {
    printf '\0no-custom\x1ftrue\n'
    printf '\0message\x1f%s now?\n' "$1"
    row "Yes, $1" "$2" "$3!"
    row "Back"    go-previous-symbolic back
}

# Detached so the action outlives rofi, which exits once this script returns.
detach() { setsid -f "$@" >/dev/null 2>&1; }

case "${ROFI_INFO:-}" in
    ""|back)   menu ;;
    lock)      detach loginctl lock-session ;;
    suspend)   detach systemctl suspend ;;
    logout)    confirm "log out" system-log-out-symbolic logout ;;
    logout!)   detach gnome-session-quit --logout --no-prompt ;;
    reboot)    confirm "reboot" system-reboot-symbolic reboot ;;
    poweroff)  confirm "shut down" system-shutdown-symbolic poweroff ;;
    reboot!)   detach systemctl reboot ;;
    poweroff!) detach systemctl poweroff ;;
esac
