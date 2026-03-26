#!/bin/bash

# Defaults
ITERATIONS=5
INTERVAL=30
SERVER_ID=""
SECURE_OPT="--secure" # По умолчанию включено

BLUE='\033[0;94m'
BLUE_LIGHT='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

DIVIDER_LEN=60

PUBLIC_IP=$(curl -s https://api.myip.com)

function repeat() {
  seq -s- "$1" | tr -d '[:digit:]';
}

function blue() { echo -n -e "${BLUE}$1${NC}"; }
function blue_light() { echo -n -e "${BLUE_LIGHT}$1${NC}"; }
function divider() {
  local len=$((ITERATIONS * 7 + 10))
  if [ $len -gt $DIVIDER_LEN ]; then
    repeat $len;
  else
      repeat $DIVIDER_LEN;
  fi
}
function join {
    foo=(a "b c" d)
    return $(IFS=, ; echo "${foo[*]}")
}


# Restore cursor and clean up temp files
cleanup() {
    tput cnorm
    rm -f /tmp/speedtest_raw
    exit
}

function confirm_or_exit() {
  echo ""
  while true; do
      read -p "$1: [Y/n] " yn
      case $yn in
          [Yy]* ) break;;
          [Nn]* ) exit 0;;
          * ) echo "Please enter Yy|Nn";;
      esac
  done
}

# Catch interrupt (Ctrl+C)
trap cleanup SIGINT SIGTERM

# Check requirements
install_pkg_tip() {
    local install_command=""
    echo "Utilities '$1' not found."
    echo "You can install it using one of the following commands:"

    # Package manager hint
    if command -v apt &> /dev/null; then
        install_command="sudo apt update && sudo apt install $1"
    elif command -v brew &> /dev/null; then
        install_command="brew install $1"
    elif command -v yum &> /dev/null; then
        install_command="sudo yum install $1"
    else
      echo "  Package manager is not recognized. Please install package $1 manualy"
      exit 1
    fi
    echo -e "${BLUE}  ${install_command}${NC}"
    confirm_or_exit "Run installation?"
    eval "${install_command}"

    divider
    echo -e "${RED}Please restart script ./speedtester.sh${NC}"
    divider
    exit 1
}

check_dependencies() {
    local deps=(speedtest-cli bc jq)
    local missed_pkgs=()

    for pkg in speedtest-cli bc jq iftop; do
        if ! command -v $pkg &> /dev/null; then
            missed_pkgs+=($pkg)
        fi
    done


    if (( ${#missed_pkgs[@]} != 0 )); then
        install_pkg_tip "${missed_pkgs[*]}"
    fi
}

# Spinner animation function
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    tput civis
    tput sc
    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        tput rc
    done
    printf "    "
    tput rc
    tput cnorm # Show cursor
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n NUMBER    Number of iterations (default: ${ITERATIONS})"
    echo "  -i NUMBER    Interval between tests in seconds (default: ${INTERVAL})"
    echo "  -s ID        Specific Speedtest server ID"
    echo "  -u           Disable secure connection (remove --secure)"
    echo "  -h           Show this help"
    exit 0
}

check_dependencies

echo "Country: $(echo $PUBLIC_IP | jq .country)"
echo "Public IP: $(echo $PUBLIC_IP | jq .ip)"
exit 1


while getopts "n:i:s:uh" opt; do
  case $opt in
    n) ITERATIONS=$OPTARG ;;
    i) INTERVAL=$OPTARG ;;
    s) SERVER_ID=$OPTARG ;;
    u) SECURE_OPT="" ;; # Отключаем secure
    h) show_help ;;
    *) show_help ;;
  esac
done

SERVER_OPT=${SERVER_ID:+"--server $SERVER_ID"}
download_results=()
upload_results=()
success_count=0
fail_count=0

divider
echo "Starting (Iterations: ${ITERATIONS}, Interval: ${INTERVAL}s, Server: ${SERVER_ID:-Auto})"
divider

for (( count=1; count<=ITERATIONS; count++ )); do
    printf "Test %3d of %-3d: " "$count" "$ITERATIONS"

    # Run speedtest in background
    (speedtest $SECURE_OPT $SERVER_OPT --csv 2>/dev/null) > /tmp/speedtest_raw &
    SPEEDTEST_PID=$!

    show_spinner $SPEEDTEST_PID

    wait $SPEEDTEST_PID

    raw_data=$(cat /tmp/speedtest_raw)
    rm -f /tmp/speedtest_raw

    if [ -z "$raw_data" ]; then
        dl=0; ul=0
        ((fail_count++))
        echo -e "${RED}⚠️  Error${NC}"
    else
        dl_raw=$(echo "$raw_data" | cut -d',' -f7)
        ul_raw=$(echo "$raw_data" | cut -d',' -f8)
        dl=$(echo "scale=2; $dl_raw / 1000000" | bc -l)
        ul=$(echo "scale=2; $ul_raw / 1000000" | bc -l)
        ((success_count++))
        printf "⬇️  ${BLUE}%8s${NC} Mbit/s  |  ⬆️  ${BLUE_LIGHT}%8s${NC} Mbit/s\n" "${dl}" "${ul}"
    fi

    download_results+=("$dl")
    upload_results+=("$ul")

    [ "$count" -lt "$ITERATIONS" ] && sleep "$INTERVAL"
done



# --- Summary ---
sum_dl=0; sum_ul=0
for d in "${download_results[@]}"; do sum_dl=$(echo "$sum_dl + $d" | bc -l); done
for u in "${upload_results[@]}"; do sum_ul=$(echo "$sum_ul + $u" | bc -l); done

avg_dl=0; avg_ul=0
if [ $success_count -gt 0 ]; then
    avg_dl=$(echo "scale=2; $sum_dl / $success_count" | bc -l)
    avg_ul=$(echo "scale=2; $sum_ul / $success_count" | bc -l)
fi

echo -e "\n"

divider

echo -e " SUMMARY"

divider

printf " Success Tests:   %d\n" "$success_count"
printf " Failed Tests:    %d\n" "$fail_count"
printf " Avg Download:    ${BLUE}%s${NC} Mbit/s\n" "$avg_dl"
printf " Avg Upload:      ${BLUE_LIGHT}%s${NC} Mbit/s\n" "$avg_ul"

divider

# --- Graph Generation ---
echo -e "\n"

divider

echo -e " SUMMARY CHART (Mbit/s) ${BLUE}▓▓${NC} = Download,  ${BLUE_LIGHT}▓▓${NC} = Upload"

divider

max_val=1
for v in "${download_results[@]}" "${upload_results[@]}"; do
    if (( $(echo "$v > $max_val" | bc -l) )); then max_val=$v; fi
done
scale_step=$(echo "scale=2; $max_val / 10" | bc -l)

for (( line=10; line>=1; line-- )); do
    threshold=$(echo "scale=2; $scale_step * $line" | bc -l)
    printf "%7s |" "$threshold"
    for i in "${!download_results[@]}"; do
        if (( $(echo "${download_results[$i]} >= $threshold" | bc -l) && $(echo "${download_results[$i]} > 0" | bc -l) )); then
            blue " ▓▓"
        else printf "   "; fi

        if (( $(echo "${upload_results[$i]} >= $threshold" | bc -l) && $(echo "${upload_results[$i]} > 0" | bc -l) )); then
            blue_light "▒▒ "
        else printf "   "; fi

        printf "|"
    done
    echo ""
done

divider

printf "        "
for i in "${!download_results[@]}"; do printf "|  %-3s " "$((i+1))"; done
echo -e "\n"

divider
