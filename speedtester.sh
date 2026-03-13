#!/bin/bash

# Defaults
ITERATIONS=5
INTERVAL=30
SERVER_ID=""

BLUE='\033[0;94m'
BLUE_LIGHT='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

DIVIDER_LEN=60

# Restore cursor and clean up temp files
cleanup() {
    tput cnorm
    rm -f /tmp/speedtest_raw
    exit
}

# Catch interrupt (Ctrl+C)
trap cleanup SIGINT SIGTERM

# Check requirements
check_dependencies() {
    local missing_speedtest=false
    local missing_bc=false

    if ! command -v speedtest &> /dev/null; then
        missing_speedtest=true
    fi

    if ! command -v bc &> /dev/null; then
        missing_bc=true
    fi

    if [ "$missing_speedtest" = true ] || [ "$missing_bc" = true ]; then
        echo -e "${RED}Error: Required utilities are not installed.${NC}"
        local package="speedtest-cli"

         if [ "$missing_bc" = true ]; then
          package="bc"
         fi

        echo "Utility '${package}' not found."
        echo "You can install it using one of the following commands:"

        # Package manager hint
        if command -v apt &> /dev/null; then
          echo -e "${BLUE}  sudo apt update && sudo apt install ${package}${NC}"
        elif command -v brew &> /dev/null; then
          echo -e "${BLUE}  brew install ${package}${NC}"
        elif command -v yum &> /dev/null; then
          echo -e "${BLUE}  sudo yum install ${package}${NC}"
        else
          echo "  Please visit https://www.speedtest.net/apps/cli for instructions."
        fi

        exit 1
    fi
}

# Spinner animation function
show_spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'

    tput civis # Hide cursor
    tput sc    # Save cursor position

    while kill -0 "$pid" 2>/dev/null; do
        local temp=${spinstr#?}
        # Print symbol at saved position
        printf " [%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        tput rc # Restore cursor position
    done

    # Clear spinner area (4 spaces)
    printf "    "
    tput rc
    tput cnorm # Show cursor
}

# Help function
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -n NUMBER   Number of iterations (default: ${ITERATIONS})"
    echo "  -i NUMBER   Interval between tests in seconds (default: ${INTERVAL})"
    echo "  -s ID       Specific Speedtest server ID"
    echo "  -h          Show this help"
    exit 0
}

check_dependencies

while getopts "n:i:s:h" opt; do
  case $opt in
    n) ITERATIONS=$OPTARG ;;
    i) INTERVAL=$OPTARG ;;
    s) SERVER_ID=$OPTARG ;;
    h) show_help ;;
    *) show_help ;;
  esac
done

SERVER_OPT=${SERVER_ID:+"--server $SERVER_ID"}
download_results=()
upload_results=()

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

divider
echo "Starting (Iterations: ${ITERATIONS}, Interval: ${INTERVAL}s, Server: ${SERVER_ID:-Auto})"
divider

for (( count=1; count<=ITERATIONS; count++ )); do
    printf "Test %3d of %-3d: " "$count" "$ITERATIONS"

    # Run speedtest in background
    (speedtest --secure $SERVER_OPT --csv 2>/dev/null) > /tmp/speedtest_raw &
    SPEEDTEST_PID=$!

    show_spinner $SPEEDTEST_PID

    wait $SPEEDTEST_PID

    raw_data=$(cat /tmp/speedtest_raw)
    rm -f /tmp/speedtest_raw

    if [ -z "$raw_data" ]; then
        dl=0; ul=0
        echo "⚠️  Test error"
    else
        dl_raw=$(echo "$raw_data" | cut -d',' -f7)
        ul_raw=$(echo "$raw_data" | cut -d',' -f8)
        dl=$(echo "scale=2; $dl_raw / 1000000" | bc -l)
        ul=$(echo "scale=2; $ul_raw / 1000000" | bc -l)
        printf "⬇️  ${BLUE}%8s${NC} Mbit/s  |  ⬆️  ${BLUE_LIGHT}%8s${NC} Mbit/s\n" "${dl}" "${ul}"
    fi

    download_results+=("$dl")
    upload_results+=("$ul")

    if [ "$count" -lt "$ITERATIONS" ]; then
        sleep "$INTERVAL"
    fi
done

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
