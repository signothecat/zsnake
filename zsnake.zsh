#!/usr/bin/env zsh
# zsnake.zsh — prototype

set -o errexit   # Exit immediately if a command fails
set -o nounset   # Treat unset variables as an error
set -o pipefail  # Fail if any command in a pipeline fails

########################################

# Config

########################################

# ---------- Game Play Settings ------------

# Play Area Width and Height
GRID_W=16
GRID_H=14

# Play Speed (smaller number = faster, default is 100)
TICK_MS=${SNAKE_TICK_MS:-130}

# ---------------- CELL_W ---------------------
# Width of a single grid cell in terminal characters
CELL_W=${CELL_W:-2}

# ----------------- Cells ---------------------
# █ / ▓ / ▒ / ░ / ■

# field (must have same char count as CELL_W)
FIELD_CELL=${FIELD_CELL:-$'░░'}

# snake
SNAKE_CELL_CHAR=${SNAKE_CELL_CHAR:-"■ "}  # char count must be 1 or 2
SNAKE_CELL="$(printf "%-${CELL_W}s" "$SNAKE_CELL_CHAR")"  # Pad with spaces to fit CELL_W if necessary

# snake cell char choices (must have same char count as CELL_W)
SNAKE_CELL_CHAR_SQ=${SNAKE_CELL_CHAR_SQ:-"■ "}         # default
SNAKE_CELL_CHAR_FILL=${SNAKE_CELL_CHAR_FILL:-"██"}
SNAKE_CELL_CHAR_DEEP=${SNAKE_CELL_CHAR_DEEP:-"▓▓"}
SNAKE_CELL_CHAR_MEDIUM=${SNAKE_CELL_CHAR_MEDIUM:-"▒▒"}
SNAKE_CELL_CHAR_LIGHT=${SNAKE_CELL_CHAR_LIGHT:-"░░"}

# field char choices (must have same char count as CELL_W)
FIELD_CELL_CHAR_FILL=${SNAKE_CELL_CHAR_FILL:-"██"}
FIELD_CELL_CHAR_DEEP=${SNAKE_CELL_CHAR_DEEP:-"▓▓"}
FIELD_CELL_CHAR_MEDIUM=${SNAKE_CELL_CHAR_MEDIUM:-"▒▒"}
FIELD_CELL_CHAR_LIGHT=${SNAKE_CELL_CHAR_LIGHT:-"░░"}   # default
FIELD_CELL_CHAR_BLANK=${SNAKE_CELL_CHAR_BLANK:-"  "}

# borders (must be consistent with BORDER_W and BORDER_P)
LEFT_BORDER_CHAR=${LEFT_BORDER_CHAR:-"│ "}
RIGHT_BORDER_CHAR=${RIGHT_BORDER_CHAR:-" │"}

# ----------------- Char Numbers -------------------

# border width (bar)
LEFT_BORDER_W=${LEFT_BORDER_W:-1}

# border height
BORDER_H=${BORDER_H:-1}  # fixed

# border padding (spaces)
LEFT_BORDER_P=${LEFT_BORDER_P:-1}
RIGHT_BORDER_P=${RIGHT_BORDER_P:-1}

# Total grid width in terminal characters (GRID_W cells * CELL_W characters per cell)
GRID_PIX_W=$(( GRID_W * CELL_W ))

# header height
HEADER_H=${HEADER_H:-2}  # fixed

# box height
BOX_H=$(( BORDER_H * 2 + GRID_H ))  # GRID_H + 2

BOX_LEN=$(( GRID_PIX_W + LEFT_BORDER_P + RIGHT_BORDER_P ))

# Footer height
FOOTER_H_PLAY=${FOOTER_H_PLAY:-2}  # in play. fixed.
FOOTER_H_GAMEOVER=${FOOTER_H_GAMEOVER:-1}  # in game over screen. fixed.

# ------------------- Colors ----------------------

# ANSI Color Codes
# 0 = Black
# 1 = Red
# 2 = Green
# 3 = Yellow
# 4 = Blue
# 5 = Magenta
# 6 = Cyan
# 7 = White

if command -v tput >/dev/null 2>&1; then
  COLOR_RESET=$(tput sgr0)
  COLOR_SNAKE=$(tput setaf 2)
  COLOR_HEAD=$(tput setaf 2)
  COLOR_TEXT=$(tput setaf 7)
  COLOR_BORDER=$(tput setaf 4)
  COLOR_FIELD=$(tput setaf 2)
  COLOR_FOOD=$(tput setaf 3)
else
  COLOR_RESET=""
  COLOR_SNAKE=""
  COLOR_HEAD=""
  COLOR_TEXT=""
  COLOR_BORDER=""
  COLOR_FIELD=""
  COLOR_FOOD=""
fi

########################################

# Constants / Variables

########################################

# Score variable
SCORE=${SCORE:-0}

# Text bold
BOLD_ON=$'\e[1m'
BOLD_OFF=$'\e[22m'

########################################

# Runtime State (mutable globals)
# - Current game mode and per-frame flags
# - Snake body and movement vectors
# - Logic -> Render handoff flags

########################################

state="START_MENU"        # current game state
NEED_REDRAW=0             # request full redraw
BORDERS_DRAWN=0           # borders drawn (lazy init)
FIRST_STEP_DONE=0         # first movement completed

LAST_TAIL="" LAST_HEAD="" LAST_PREV_HEAD=""    # incremental draw keys
FOOD=""                                        # "x,y" or empty
ATE=0 COLLIDED=0 SCORE_DIRTY=0 DEATH_CAUSE=""  # logic->render flags + cause of death

typeset -a snake
snake=()                    # body as ["x,y", ...]
dx=1; dy=0                  # current direction
want_dx=1; want_dy=0        # desired direction (from input)

########################################

# Terminal Controls

########################################

restore_term() {
  printf "%s" "${COLOR_RESET}"
  if command -v tput >/dev/null 2>&1; then
    tput cnorm
  fi
  stty sane 2>/dev/null || true
}

setup_term() {
  stty -echo -icanon time 0 min 0 2>/dev/null || true
  if command -v tput >/dev/null 2>&1; then
    tput civis
  fi
}

# Cleanup handler: ensure screen is cleared and terminal is restored
on_exit() {
  clear_screen
  restore_term
}

# Always run cleanup on exit or interruption
trap on_exit EXIT INT TERM

########################################

# Drawing Logic

########################################

# ----------------- Clear Functions ---------------------

# Clear the entire terminal screen and move cursor to top-left
clear_screen() {
  if command -v tput >/dev/null 2>&1; then
    tput clear
    tput cup 0 0
  else
    printf "\033[2J\033[H"
  fi
}

# Clear from cursor position to the end of the current line
clear_eol() {
  if command -v tput >/dev/null 2>&1; then
    tput el
  else
    printf "\033[K"
  fi
}

# ------------------- Menu Screen ----------------------

# Draw start menu screen (title and available key hints)
draw_start() {
  local title="z snake"
  local hint1="[s]Start"
  local hint2="[q]Quit"
  move_to 0 0; printf "%s%s%s" "$COLOR_TEXT" "$title" "$COLOR_RESET"
  move_to 1 0; printf "%s%s %s%s\n" "$COLOR_TEXT" "$hint1" "$hint2" "$COLOR_RESET"
}

# ------------------- Game Screen ------------------------

# game screen's header: title + score
draw_header() {
  local title="z snake"
  move_to 0 0; clear_eol; printf "%s%s%s" \
    "$COLOR_TEXT" "$title" "$COLOR_RESET"
  move_to 1 0; clear_eol; printf "%s%sScore: %d%s%s" \
    "$COLOR_TEXT" "$BOLD_ON" "$SCORE" "$BOLD_OFF" "$COLOR_RESET"
}

# field borders
draw_borders() {
  # reference global variables
  local box_len=$((BOX_LEN))  # to use for
  local header_h=$((HEADER_H)) border_h=$((BORDER_H))
  local l_border_w=$((LEFT_BORDER_W)) l_border_p=$((LEFT_BORDER_P)) grid_pix_w=$((GRID_PIX_W))

  # top / bottom borders: extend by BOX_LEN
  move_to $((header_h)) 0; printf "┌"; draw_repeat "─" "$box_len"; printf "┐"
  move_to $((header_h + border_h + GRID_H)) 0; printf "└"; draw_repeat "─" "$box_len"; printf "┘"

  # left / right borders
  for (( y=0; y<GRID_H; y++ )); do
    move_to $((header_h + border_h + y)) 0; printf "%s" "$LEFT_BORDER_CHAR"
    move_to $((header_h + border_h + y)) $((l_border_w + l_border_p + grid_pix_w)); printf "%s" "$RIGHT_BORDER_CHAR"
  done

  draw_food  # will be moved to appropriate section

  # bottom: keybinding help moved here
  move_to $((HEADER_H + BOX_H)) 0; printf "%s[p/space]Toggle Pause%s" "$COLOR_TEXT" "$COLOR_RESET"
  move_to $((HEADER_H + BOX_H + 1)) 0; printf "%s[r]Retry | [b]Back | [q]Quit%s" "$COLOR_TEXT" "$COLOR_RESET"

  BORDERS_DRAWN=1
}

# play screen
draw_play() {
  clear_screen
  draw_header
  draw_borders
  typeset -A occ; occ=()
  local p
  for p in ${snake[@]}; do occ[$p]=1; done
  local headk=${snake[-1]}
  local y x key row col
  for (( y=0; y<GRID_H; y++ )); do
    row=$((3+y))
    for (( x=0; x<GRID_W; x++ )); do
      col=$((LEFT_BORDER_W + LEFT_BORDER_P + x*CELL_W))
      key=$(pos_key $x $y)
      move_to $row $col
      if [[ -n ${occ[$key]:-} ]]; then
        if [[ $key == $headk ]]; then
          printf "%s%s%s" "$COLOR_HEAD" "$SNAKE_CELL" "$COLOR_RESET"
        else
          printf "%s%s%s" "$COLOR_SNAKE" "$SNAKE_CELL" "$COLOR_RESET"
        fi
      elif [[ $key == $FOOD ]]; then
        printf "%s%s%s" "$COLOR_FOOD" "$SNAKE_CELL" "$COLOR_RESET"
      else
        printf "%s" "$COLOR_FIELD"; draw_repeat "$FIELD_CELL" 1; printf "%s" "$COLOR_RESET"
      fi
    done
  done
}

# ------------------- Snake ---------------------

draw_step() {
  # Draw borders once (lazy initialization)
  if (( ! BORDERS_DRAWN )); then
    draw_borders
  fi

  local tail=$1
  local head=$2

  # Erase the tail cell if it moved
  if [[ -n $tail ]]; then
    local tx=${tail%%,*}
    local ty=${tail##*,}
    move_to $((HEADER_H + BORDER_H + ty)) $((LEFT_BORDER_W + LEFT_BORDER_P + tx*CELL_W)); printf "%s%s%s" "$COLOR_FIELD" "$FIELD_CELL" "$COLOR_RESET"
  fi

  # Recolor previous head (now part of body) if it wasn't erased
  if [[ -n ${LAST_PREV_HEAD} && ${LAST_PREV_HEAD} != ${tail} ]]; then
    local px=${LAST_PREV_HEAD%%,*}
    local py=${LAST_PREV_HEAD##*,}
    move_to $((HEADER_H + BORDER_H + py)) $((LEFT_BORDER_W + LEFT_BORDER_P + px*CELL_W)); printf "%s%s%s" "$COLOR_SNAKE" "$SNAKE_CELL" "$COLOR_RESET"
  fi

  # Draw the new head in specified color
  local hx=${head%%,*}
  local hy=${head##*,}
  move_to $((HEADER_H + BORDER_H + hy)) $((LEFT_BORDER_W + LEFT_BORDER_P + hx*CELL_W)); printf "%s%s%s" "$COLOR_HEAD" "$SNAKE_CELL" "$COLOR_RESET"

  # Ensure new food is drawn right away (maybe should be moved to more appropriate section)
  draw_food

  # Move cursor below field (avoid leaving cursor inside)
  move_to $((HEADER_H + BOX_H + FOOTER_H_PLAY)) 0
}

# ---------------------- Food -------------------------

# random spawning food
draw_food() {
  [[ -z ${FOOD} ]] && return
  local fx=${FOOD%%,*}
  local fy=${FOOD##*,}
  move_to $((HEADER_H + BORDER_H + fy)) $((LEFT_BORDER_W + LEFT_BORDER_P + fx*CELL_W)); printf "%s%s%s" "$COLOR_FOOD" "$SNAKE_CELL" "$COLOR_RESET"
}

########################################

# Game State Logic

########################################

init_snake() {
  local cx=$((GRID_W/2))
  local cy=$((GRID_H/2))
  snake=( $(pos_key $((cx-1)) $cy) $(pos_key $cx $cy) $(pos_key $((cx+1)) $cy) )
  dx=1; dy=0; want_dx=$dx; want_dy=$dy
  LAST_TAIL=""; LAST_HEAD=""; SCORE=0
  NEED_REDRAW=1
  BORDERS_DRAWN=0
  FIRST_STEP_DONE=0
  # reset logic to render flags
  ATE=0; COLLIDED=0; SCORE_DIRTY=0; DEATH_CAUSE=""
  # (re)spawn food ...
  FOOD=""
  spawn_food
}

# Place new food on a random free cell of the grid
spawn_food() {
  # Create an associative array to mark occupied positions
  typeset -A occ; occ=()
  local s
  # Mark all snake body cells as occupied
  for s in ${snake[@]}; do occ[$s]=1; done

  # Calculate number of free cells
  local free=$(( GRID_W*GRID_H - ${#snake[@]} ))
  if (( free <= 0 )); then
    # No space left -> no food can be spawned
    FOOD=""
    return
  fi
  local x y k
  while true; do
    # Pick a random cell coordinate
    x=$((RANDOM % GRID_W))
    y=$((RANDOM % GRID_H))
    k=$(pos_key $x $y)
    # If the cell is not occupied by the snake, place food there
    if [[ -z ${occ[$k]:-} ]]; then
      FOOD=$k
      break
    fi
  done
}

# Update snake position and state for one tick
update_snake() {
  # Reset per-tick flags (COLLIDED kept for backward compatibility)
  ATE=0; DEATH_CAUSE=""; COLLIDED=0

  # Get current tail and head positions
  local tail=${snake[1]}
  local head=${snake[-1]}
  local hx=${head%%,*}
  local hy=${head##*,}

  # Calculate new head position
  local nx=$((hx + dx))
  local ny=$((hy + dy))

  # --- Wall collision ---
  if (( nx < 0 || nx >= GRID_W || ny < 0 || ny >= GRID_H )); then
    DEATH_CAUSE="WALL"; COLLIDED=1
    return
  fi

  # Convert new position to key
  local new=$(pos_key $nx $ny)

  # --- Food check ---
  if [[ -n $FOOD && $new == $FOOD ]]; then
    ATE=1
  fi

  # --- Self-collision ---
  # Build occupancy map (allow stepping into the current tail if not eating)
  typeset -A occ; occ=()
  local s
  for s in ${snake[@]}; do occ[$s]=1; done
  if (( ! ATE )); then unset 'occ[$tail]'; fi
  if [[ -n ${occ[$new]:-} ]]; then
    DEATH_CAUSE="SELF"; COLLIDED=1
    return
  fi

  # --- Normal update flow ---
  snake+=$new
  if (( ATE )); then
    # Snake grows: tail remains
    LAST_TAIL=""
    SCORE=$((SCORE+1))
    SCORE_DIRTY=1
  else
    # Snake moves: drop the tail
    snake=(${snake[@]:1})
    LAST_TAIL=$tail
  fi

  # Update head tracking
  LAST_PREV_HEAD=$head
  LAST_HEAD=$new
  FIRST_STEP_DONE=1

  # Spawn new food if eaten
  if (( ATE )); then
    spawn_food
  fi
}


# Apply the desired direction (want_dx, want_dy) to the current movement (dx, dy)
apply_direction() { dx=$want_dx; dy=$want_dy; }

########################################

# Utility Helpers

########################################

# Helper functions for positions, movement, and timing

# Current time in milliseconds (robust across environments)
now_ms() {
  # Prefer zsh/datetime's EPOCHREALTIME if available
  if zmodload -e zsh/datetime 2>/dev/null || zmodload zsh/datetime 2>/dev/null; then
    printf '%.0f' "$(( EPOCHREALTIME * 1000 ))"
    return
  fi
  # Fallback: Perl High-Resolution timer
  if command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes -e 'printf("%d", int(Time::HiRes::time()*1000))'
    return
  fi
  # Fallback: zsh printf epoch seconds (no ms precision)
  if printf '%(%s)T' -1 >/dev/null 2>&1; then
    printf '%s000' "$(printf '%(%s)T' -1)"
    return
  fi
  # Last resort
  date +%s 2>/dev/null | awk '{printf "%s000", $1}'
}

draw_repeat() {
  local ch="$1" n=$2
  local s
  s=$(printf "%*s" "$n" "")
  s=${s// /$ch}
  printf "%s" "$s"
}

# Convert (x, y) grid coordinates into a "x,y" string key
pos_key() { printf "%d,%d" "$1" "$2"; }

# Move the terminal cursor to the given (row, col) position
move_to() {
  if command -v tput >/dev/null 2>&1; then
    tput cup "$1" "$2"
  else
    printf "\033[%d;%dH" "$(( $1 + 1 ))" "$(( $2 + 1 ))"
  fi
}

# Sleep for a given number of milliseconds (uses Perl if available, otherwise awk + sleep)
msleep() {
  local ms=${1:-100}  # Get the first argument as milliseconds (default: 100)
  if command -v perl >/dev/null 2>&1; then  # If 'perl' command is available
    perl -e 'select undef, undef, undef, $ARGV[0]/1000' "$ms"  # Use Perl to sleep for ms/1000 seconds
  else
    local s
    s=$(printf "%s" "$ms" | awk '{printf "%.3f", $1/1000}')  # Convert ms to seconds with 3 decimals using awk (just divides ms by 1000)
    sleep "$s"  # Sleep using 'sleep' command (seconds)
  fi
}

########################################

# Input Handler

########################################

read_input() {
  local k rest third
  if read -k 1 -s -t 0 k 2>/dev/null; then
        if [[ $state == START_MENU ]]; then
      case "$k" in
        s|S)
          state="PLAYING"
          init_snake
          return
          ;;
        q|Q)
          clear_screen
          exit 0
          ;;
        $'\e')  # drain ESC sequence = allow
          read -k 1 -s -t 0.02 rest  2>/dev/null || return
          read -k 1 -s -t 0.02 third 2>/dev/null || true
          return
          ;;
        *)  # ignore other keys
          return
          ;;
      esac
    elif [[ $state == GAMEOVER ]]; then
      case "$k" in
        r|R)
          state="PLAYING"
          init_snake
          return
          ;;
        b|B)
          state="START_MENU"
          clear_screen
          draw_start
          NEED_REDRAW=0
          BORDERS_DRAWN=0
          FIRST_STEP_DONE=0
          return
          ;;
        q|Q)
          clear_screen
          exit 0
          ;;
        $'\e')  # drain ESC sequence = allow
          read -k 1 -s -t 0.02 rest  2>/dev/null || return
          read -k 1 -s -t 0.02 third 2>/dev/null || true
          return
          ;;
        *)  # ignore other keys
          return
          ;;
      esac
    elif [[ $state == PAUSED ]]; then
      case "$k" in
        q|Q)
          clear_screen
          exit 0
          ;;
        p|P|$' ')
          state="PLAYING"
          clear_paused
          return
          ;;
        b|B)
          state="START_MENU"
          clear_screen
          draw_start
          NEED_REDRAW=0
          BORDERS_DRAWN=0
          FIRST_STEP_DONE=0
          return
          ;;
        r|R)
          state="PLAYING"
          init_snake
          return
          ;;
        $'\e')  # drain ESC sequence allow
          read -k 1 -s -t 0.02 rest  2>/dev/null || return
          read -k 1 -s -t 0.02 third 2>/dev/null || true
          return
          ;;
        *)  # ignore other keys
          return
          ;;
      esac
    fi
    if [[ $k == $'\e' ]]; then
      if read -k 1 -s -t 0.0001 rest 2>/dev/null && [[ $rest == "[" ]]; then
        if read -k 1 -s -t 0.0001 rest 2>/dev/null; then
          case "$rest" in
            A) [[ $state == PLAYING ]] && set_want 0 -1;;  # UP arrow
            B) [[ $state == PLAYING ]] && set_want 0 1;;   # DOWN arrow
            C) [[ $state == PLAYING ]] && set_want 1 0;;   # RIGHT arrow
            D) [[ $state == PLAYING ]] && set_want -1 0;;  # LEFT arrow
          esac
        fi
      fi
      return
    fi
    case "$k" in
      q|Q)
        clear_screen
        exit 0;;
      p|P|" ")
        if [[ $state == "PLAYING" ]]; then
          state="PAUSED"
          show_paused
        elif [[ $state == "PAUSED" ]]; then
          state="PLAYING"
          clear_paused
        fi
        ;;
      r|R)
        state="PLAYING"
        init_snake
        return
        ;;
      s|S)
        if [[ $state == START_MENU ]]; then
          state="PLAYING"; init_snake; return
        elif [[ $state == PLAYING ]]; then
          set_want 0 1                                 # DOWN
        fi
        ;;
      w|W) [[ $state == PLAYING ]] && set_want 0 -1;;  # UP
      a|A) [[ $state == PLAYING ]] && set_want -1 0;;  # LEFT
      d|D) [[ $state == PLAYING ]] && set_want 1 0;;   # RIGHT
      h|H) [[ $state == PLAYING ]] && set_want -1 0;;  # LEFT
      j|J) [[ $state == PLAYING ]] && set_want 0 1;;   # DOWN
      k|K) [[ $state == PLAYING ]] && set_want 0 -1;;  # UP
      l|L) [[ $state == PLAYING ]] && set_want 1 0;;   # RIGHT
      b|B)
        if [[ $state == "PLAYING" || $state == "PAUSED" ]]; then
          state="START_MENU"
          clear_screen
          draw_start
          NEED_REDRAW=0
          BORDERS_DRAWN=0
          FIRST_STEP_DONE=0
        fi
        ;;
    esac
  fi
}

# Update the desired direction (want_dx, want_dy) based on player input
set_want() {
  local ndx=$1 ndy=$2

  # Prevent reversing direction directly (snake cannot go back into itself)
  if (( ndx == -dx && ndy == -dy )); then
    return
  fi

  # Only accept direction changes after the first move has done
  if (( FIRST_STEP_DONE == 1 )); then
    want_dx=$ndx; want_dy=$ndy
  fi
}

########################################

# State Overlays (Paused / Game Over)

########################################

show_paused() {
  move_to $((GRID_H/2)) $((LEFT_BORDER_W + LEFT_BORDER_P + GRID_PIX_W/2 - 3)); printf "%sPAUSED%s" "$COLOR_TEXT" "$COLOR_RESET"
  move_to $((HEADER_H + BOX_H + FOOTER_H_PLAY)) 0
}

clear_paused() {
  move_to $((GRID_H/2)) $((LEFT_BORDER_W + LEFT_BORDER_P + GRID_PIX_W/2 - 3)); printf "%s" "$COLOR_FIELD"; draw_repeat "$FIELD_CELL" 6; printf "%s" "$COLOR_RESET"
  move_to $((HEADER_H + BOX_H + FOOTER_H_PLAY)) 0
}

show_gameover() {
  move_to $((GRID_H/2)) $((LEFT_BORDER_W + LEFT_BORDER_P + GRID_PIX_W/2 - 5)); printf "%sGAME OVER%s" "$COLOR_TEXT" "$COLOR_RESET"
  move_to $((HEADER_H + BOX_H)) 0; clear_eol; printf "%s[r]Retry, [b]Back, [q]Quit%s" "$COLOR_TEXT" "$COLOR_RESET"
  move_to $((HEADER_H + BOX_H + 1)) 0; clear_eol
  move_to $((HEADER_H + BOX_H + FOOTER_H_GAMEOVER)) 0
}

########################################

# Main Loop

########################################

main() {
  setup_term
  clear_screen
  draw_start
  while true  # infinity loop
  do
    local frame_start_ms=$(now_ms)
    read_input
    case $state in
      START_MENU)
        ;;
      PLAYING)
        if (( NEED_REDRAW )); then
          draw_play
          NEED_REDRAW=0
        else
          apply_direction
          update_snake
          if [[ -n $DEATH_CAUSE ]]; then
            state="GAMEOVER"
            show_gameover
          else
            # mark first step only once, after the first successful move
            if (( FIRST_STEP_DONE == 0 )); then
              FIRST_STEP_DONE=1
            fi
            draw_step "$LAST_TAIL" "$LAST_HEAD"
            (( SCORE_DIRTY )) && { draw_header; SCORE_DIRTY=0; }
          fi
        fi
        ;;
      PAUSED)
        ;;
      GAMEOVER)
        ;;
    esac
    { # sleep ( TICK_MS - elapsed time(time spent so far) )
      # calculate remain_ms to sleep
      local remain_ms=$(( TICK_MS - ( $(now_ms) - frame_start_ms ) ))
      # convert remain_ms (ms -> s) with awk then pass to sleep
      (( remain_ms > 0 )) && sleep "$(awk -v ms=$remain_ms 'BEGIN{printf "%.3f", ms/1000}')"
    }
  done
}

# ---- Entry point: start the game by calling main() ------
main "$@"
