#!/usr/bin/env bash

set +e

TODO_PATH="${TODO_PATH:-$HOME/todo.txt}"

YYYYMMDD=+%Y-%m-%d
DDMMYY=+%d-%m-%y

NUMBER_RE='^[0-9]+$'

if [[ -t 1 ]]; then
  TERMINAL_OUTPUT=1
  COLOR_RED_BOLD=$(echo -e "\e[1;31m")
  COLOR_YELLOW_BOLD=$(echo -e "\e[1;33m")
  COLOR_BLUE_BOLD=$(echo -e "\e[1;34m")
  COLOR_CYAN_BOLD=$(echo -e "\e[1;36m")
  COLOR_GREEN_BOLD=$(echo -e "\e[1;32m")
  COLOR_RESET=$(echo -e "\e[0m")
fi

usage() {
  echo "usage:" >&2
  echo "  $0 [-f] [-n] [-a] [DAYS] -- show TODOs for next DAYS" >&2
  echo "     -n print the id for each entry" >&2
  echo "     -f always prints the full date" >&2
  echo "     -a show all (including done)" >&2
  echo "" >&2
  echo "  $0 -m [UNTIL] MSG   -- add TODO" >&2
  echo "     UNTIL could be:" >&2
  echo "       DD[-MM[-YY]]   until date" >&2
  echo "       +N{d|w|m|y}    until today + N days/weeks/months/years" >&2
  echo "       [+]0           until the end of a day" >&2
  echo "       {mon[day]|...} until the next day of the week" >&2
  echo "" >&2
  echo "  $0 -d ID            -- mark TODO done by ID " >&2
  echo "" >&2
  echo "  $0 -r ID            -- remove TODO with by ID" >&2
}

invalid_usage() {
  usage
  exit 1
}

leading_zero() {
  if [[ -z "$1" || "${#1}" -eq 2 ]]; then
    echo "$1"
  else
    echo "0$1"
  fi
}

# parse $1 in dd-mm-yy format, convert to YYYY-mm-dd (readable by `date`)
parse_ddmmyy() {
  DATE_RE='^([0-9]{1,2})(-([0-9]{1,2}))?(-([0-9]{1,2}))?$'
  if ! [[ "$1" =~ $DATE_RE ]]; then
    return 1
  fi
  dd=$(leading_zero "${BASH_REMATCH[1]}")
  mm=$(leading_zero "${BASH_REMATCH[3]}")
  yy=$(leading_zero "${BASH_REMATCH[5]}")
  if [[ -z "$mm" ]]; then
    mm=$(date +%m)
  fi
  if [[ -z "$yy" ]]; then
    yy=$(date +%y)
  fi
  # validate
  date -u --date="20$yy-$mm-$dd" "$YYYYMMDD"
}

# print $1 date of yyyy-mm-dd format in dd-mm-yy format.
date_ddmmyy() {
  date --date="$1" "$DDMMYY"
}

# parse $1, convert to YYYY-mm-dd
calc_date() {
  PLUS_INTERVAL_RE='^\+([0-9]+)(d|w|m|y)$'
  DAY_OF_WEEK='^mon(day)?|tue(sday)?|wed(nesday)?|thu(rsday)?|fri(day)?|sat(urday)?|sun(day)?$'
  if [[ "$1" == "+0" || "$1" == "0" ]]; then
    date "$YYYYMMDD"
  elif [[ "$1" =~ $PLUS_INTERVAL_RE ]]; then
    n="${BASH_REMATCH[1]}"
    p="${BASH_REMATCH[2]}"
    case "$p" in
      "d")
        p="days" ;;
      "w")
        p="weeks" ;;
      "m")
        p="months" ;;
      "y")
        p="years" ;;
    esac
    date --date="+$n $p" "$YYYYMMDD"
  elif [[ "$1" =~ $DAY_OF_WEEK ]]; then
    date --date="next $1" "$YYYYMMDD" 
  else
    parse_ddmmyy "$1" || (echo "error: Invalid date format" >&2; return 1)
  fi
}

# add UNTIL MSG
add() {
  until=$(calc_date "$1") || invalid_usage
  printf "%s %s\n" $(date_ddmmyy "$until") "$2" >> "$TODO_PATH"
}

# todo DAYS < TODO_FILE
# 
# DAYS is in yyyy-mm-dd format
# prints lines in format: #LINENO yyyy-mm-dd ESC
todo_select_before() {
  LINE_RE='^(DONE)?\s*([0-9]{1,2}-[0-9]{1,2}-[0-9]{1,2})\s*(.*)$'
  lineno=0
  while read line; do
    ((lineno++))
    if ! [[ "$line" =~ $LINE_RE ]]; then
      continue
    fi

    done="${BASH_REMATCH[1]}"
    if [[ -n "$done" && -z "$show_all_flag" ]]; then
      continue
    fi

    date=$(parse_ddmmyy "${BASH_REMATCH[2]}") || return 1
    desc="${BASH_REMATCH[3]}"

    if ! [[ "$date" > "$1" ]]; then
      printf "%s\n" "$lineno $date $done $desc"
    fi
  done
}

# todo_pretty < SELECTED_TODOS
todo_pretty() {
  LINE_RE='^([0-9]+)\s*([-0-9]+)\s*(DONE)?\s*(.*)$'
  while read line; do
    if ! [[ "$line" =~ $LINE_RE ]]; then
      echo "$line"
      echo "error: Invalid line" >&2
      return 1
    fi

    lineno="${BASH_REMATCH[1]}"
    date="${BASH_REMATCH[2]}"
    done="${BASH_REMATCH[3]}"
    desc="${BASH_REMATCH[4]}"
    if [[ -z "$lineno_flag" ]]; then
      lineno_str=''
    else
      lineno_str="#$lineno "
    fi

    one_week_plus_date=$(date --date="+1 weeks" "$YYYYMMDD")
    today=$(date "$YYYYMMDD")
    date_color=''
    if [[ "$date" == "$today" ]]; then
      date_color="$COLOR_YELLOW_BOLD"
      date_pretty_str=Today
    elif [[ ! "$date" > "$today" ]]; then
      date_color="$COLOR_RED_BOLD"
      date_pretty_str=$(date_ddmmyy "$date")
    elif [[ ! "$date" > "$one_week_plus_date" ]]; then
      date_color="$COLOR_CYAN_BOLD"
      date_pretty_str=$(date --date="$date" +%a)
    else
      date_color="$COLOR_CYAN_BOLD"
      date_pretty_str=$(date_ddmmyy "$date")
    fi

    date_str=$(date_ddmmyy "$date")
    if [[ -z "$full_date_flag" ]]; then
      date_str="$date_pretty_str"
    fi

    done_str=''
    if [[ -n "$done" ]]; then
      done_str="${COLOR_GREEN_BOLD}DONE${COLOR_RESET} "
    fi

    desc=$(sed -r -e "s/![^![:space:]]+/$COLOR_BLUE_BOLD\0$COLOR_RESET/g" <<< "$desc")

    printf "%s\n" "$lineno_str$date_color[$date_str]$COLOR_RESET ${done_str}$desc"
  done
}

# todo DAYS
todo() {
  if [[ "$1" == "-1" ]]; then
    days=365000
  else
    if ! [[ "$1" =~ $NUMBER_RE ]]; then
       echo "error: Invalid days number" >&2
       invalid_usage
    fi
    days="$1"
  fi
  before=$(date --date="+$days days" "$YYYYMMDD") || return 1
  if [[ -z "$lineno_flag" ]]; then
    columns=2
  else
    columns=3
  fi
  todo_select_before "$before" < "$TODO_PATH" | sort -k 2 | todo_pretty | column -t -l$columns -o' '
}

# remove ID
remove() {
  if ! [[ "$1" =~ $NUMBER_RE ]]; then
     echo "error: Invalid id" >&2
     invalid_usage
  fi
  sed -r -i -e "${1}s/.*//" "$TODO_PATH"
}

# done ID
set_done() {
  if ! [[ "$1" =~ $NUMBER_RE ]]; then
     echo "error: Invalid id" >&2
     invalid_usage
  fi
  sed -r -i -e "${1}s/^[-0-9]+/DONE \0/" "$TODO_PATH"
}

if [[ "$1" == "-m" ]]; then
  shift
  [[ $# -ge 1 && $# -le 2 ]] || invalid_usage
  if [[ $# -eq 2 ]]; then
    date=$1
    shift
  else
    date=0
  fi
  desc=$1
  add "$date" "$desc"
elif [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
elif [[ "$1" == "-d" ]]; then
  shift
  [[ $# -eq 1 ]] || invalid_usage
  set_done "$1"
elif [[ "$1" == "-r" ]]; then
  shift
  [[ $# -eq 1 ]] || invalid_usage
  remove "$1"
else
  args=$(getopt -o "fna" -- "$@") || invalid_usage
  eval set -- "$args"
  while true; do
    case "$1" in
      -f)
        full_date_flag=1
        shift ;;
      -n)
        lineno_flag=1
        shift ;;
      -a)
        show_all_flag=1
        shift ;;
      --)
        shift
        break ;;
    esac
  done

  [[ $# -le 1 ]] || invalid_usage
  if [[ $# -eq 1 ]]; then
    days=$1
  else
    days=-1
  fi

  todo "$days"
fi
