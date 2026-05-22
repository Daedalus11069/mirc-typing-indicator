; Discord-like typing indicator using DCX XStatusbar
; ====================================================
; Usage:
;   /init_typing_indicator    - Initialize the typing statusbar (auto-runs on START)
;   /remove_typing_indicator  - Remove the typing statusbar
;   /test_typing <nick>       - Test the typing indicator with a nickname
;   F5                        - Toggle the typing indicator on/off
;
; The statusbar will automatically show who's typing in your active channel/PM,
; similar to Discord's "User is typing..." indicator at the bottom of the window.

; Quick toggle command
alias F5 {
  if ($xstatusbar().visible) {
    remove_typing_indicator
    echo -a * Typing indicator disabled
  }
  else {
    init_typing_indicator
    echo -a * Typing indicator enabled
  }
}

; Test command to simulate typing
alias test_typing {
  if (!$1) {
    echo -a Usage: /test_typing <nick>
    return
  }

  var %chan = $active
  if (!%chan) {
    echo -a No active window
    return
  }

  ; Simulate typing started
  set_user_typing %chan $1 active
  echo -a * Simulated typing by $1 in %chan (use /test_typing $1 again with 'done' to clear)
}

; Initialize the typing indicator statusbar
alias -l init_typing_indicator {
  ; Enable statusbar
  xstatusbar -A 1

  ; Set up 1 cell: typing indicator (auto-stretch)
  xstatusbar -l 100%

  ; Initialize typing tracking hash table
  if (!$hget(typing_users)) { hmake typing_users 100 }
}

; Remove typing indicator statusbar
alias -l remove_typing_indicator {
  xstatusbar -A 0
  if ($hget(typing_users)) { hfree typing_users }
}

; Update the typing indicator display
alias -l update_typing_display {
  if (!$hget(typing_users)) { return }

  var %chan = $active
  if (!%chan) { return }

  ; Get all users typing in this channel
  var %typing_list = $get_typing_users(%chan)

  ; Update statusbar cell 2 with typing indicator
  if (%typing_list) {
    var %display = $build_typing_display(%typing_list)
    xstatusbar -v 1 1 1 %display
  }
  else {
    xstatusbar -v 1 1 1 $chr(160)
  }
}

; Build Discord-style typing display text
alias -l build_typing_display {
  var %list = $1-
  var %count = $numtok(%list, 44)

  if (%count == 0) {
    return
  }
  elseif (%count == 1) {
    return %list is typing...
  }
  else {
    ; Build list with proper grammar: "User1, User2, and User3 are typing..."
    var %result, %i = 1
    while (%i <= %count) {
      var %nick = $gettok(%list, %i, 44)
      if (%i == 1) {
        %result = %nick
      }
      elseif (%i == %count) {
        %result = %result and %nick
      }
      else {
        %result = %result $+ , %nick
      }
      inc %i
    }
    return %result are typing...
  }
}

; Get list of users currently typing in a channel
alias -l get_typing_users {
  var %chan = $1
  var %result, %i = 1

  while (%i <= $hget(typing_users, 0).item) {
    var %item = $hget(typing_users, %i).item
    var %item_chan = $gettok(%item, 1, 247)
    var %item_nick = $gettok(%item, 2, 247)

    if (%item_chan == %chan) {
      %result = $addtok(%result, %item_nick, 44)
    }
    inc %i
  }

  return %result
}

; Set a user as typing
alias -l set_user_typing {
  var %chan = $1
  var %nick = $2
  var %state = $3
  var %key = %chan $+ $chr(247) $+ %nick

  if ((%state == active) || (%state == paused)) {
    ; User is typing - add to hash table with current timestamp
    hadd typing_users %key $ctime
  }
  elseif (%state == done) {
    ; User stopped typing - remove
    if ($hget(typing_users, %key)) {
      hdel typing_users %key
    }
  }

  ; Immediate update
  update_typing_display
}

; Clean up stale typing entries (older than 10 seconds)
alias -l cleanup_stale_typing {
  if (!$hget(typing_users)) { return }

  var %now = $ctime
  var %timeout = 10
  var %i = 1
  var %needsUpdate = $false

  while (%i <= $hget(typing_users, 0).item) {
    var %item = $hget(typing_users, %i).item
    var %timestamp = $hget(typing_users, %item)

    ; Remove if older than timeout
    if ((%now - %timestamp) > %timeout) {
      hdel typing_users %item
      %needsUpdate = $true
      ; Don't increment %i since we deleted an item
    }
    else {
      inc %i
    }
  }

  ; Update display if we removed anything
  if (%needsUpdate) {
    update_typing_display
  }
}

; Clear typing state for a specific user across all channels
alias -l clear_user_typing {
  if (!$hget(typing_users)) { return }

  var %nick = $1
  var %i = 1
  var %needsUpdate = $false

  while (%i <= $hget(typing_users, 0).item) {
    var %item = $hget(typing_users, %i).item
    var %item_nick = $gettok(%item, 2, 247)

    if (%item_nick == %nick) {
      hdel typing_users %item
      %needsUpdate = $true
      ; Don't increment since we deleted an item
    }
    else {
      inc %i
    }
  }

  if (%needsUpdate) {
    update_typing_display
  }
}

; Clear all typing states for a specific channel
alias clear_channel_typing {
  if (!$hget(typing_users)) { return }

  var %chan = $1
  var %i = 1
  var %needsUpdate = $false

  while (%i <= $hget(typing_users, 0).item) {
    var %item = $hget(typing_users, %i).item
    var %item_chan = $gettok(%item, 1, 247)

    if (%item_chan == %chan) {
      hdel typing_users %item
      %needsUpdate = $true
    }
    else {
      inc %i
    }
  }

  if (%needsUpdate) {
    update_typing_display
  }
}

raw tagmsg:*: {
  var %state = $msgtags(+typing).key
  var %chan = $1
  var %nick = $msgtags(account).key

  ; If no account tag, use the nick prefix
  if (!%nick) {
    var %nick = $nick
  }

  ; Only process if we have a valid nick and typing state
  if ((%nick) && (%state)) {
    ; Check if this is relevant to the active window
    var %splitReg = /(.)/g
    var %chantypesReg = / $+ $regsubex($regsubex($chantypes,%splitReg,\1|),/\|$/,$null)
    var %isChannel = $regex(%chan, %chantypesReg $+ /)

    var %isActive = $false

    if ((%isChannel == 1) && (%chan == $active)) {
      ; Typing in active channel
      %isActive = $true
    }
    elseif ((!%isChannel) && (%nick == $active)) {
      ; Private message with active user
      %isActive = $true
    }

    ; Update typing state if this affects the active window
    if (%isActive) {
      ; For PMs, use the sender's nick as the channel identifier
      var %trackChan = $iif(%isChannel == 1, %chan, %nick)
      set_user_typing %trackChan %nick %state
    }
  }
}

on *:ACTIVE:*: {
  ; Refresh typing display when switching windows
  update_typing_display
}

on *:START: {
  ; Auto-initialize typing indicator on mIRC start
  init_typing_indicator
}

on *:EXIT: {
  ; Cleanup on exit
  remove_typing_indicator
}

; Clean up when users part channels
on *:PART:#: {
  clear_user_typing $nick
}

; Clean up when users quit
on *:QUIT: {
  clear_user_typing $nick
}

; Clean up when closing a query/channel window
on *:CLOSE:?:,#: {
  clear_channel_typing $target
}
