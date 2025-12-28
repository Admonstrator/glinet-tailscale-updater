#!/bin/sh

# --- SETUP & KONFIGURATION ---
E=$(printf '\033')
W=${COLUMNS:-80}; H=${LINES:-24}
[ "$W" -lt 20 ] && W=80; [ "$H" -lt 10 ] && H=24

# Cursor verstecken, Schirm leeren
printf "${E}[?25l${E}[2J"
# Wichtig: Trap für sauberes Beenden bei Strg+C
trap 'printf "${E}[?25h${E}[0m${E}[2J"; exit' INT TERM

# --- ZUFALLS-POOL (einmalig generiert für Speed) ---
# Wir holen uns 600 Zahlen auf einen Schlag
RAND_POOL=$(awk -v n=600 'BEGIN { srand(); for(i=0;i<n;i++) printf "%d ", int(rand()*32767) }')

# Hilfsfunktion um Zahlen aus dem Pool zu holen
get_num() {
    local idx=$1; local max=$2; local offset=$3
    local val=$(echo "$RAND_POOL" | cut -d' ' -f"$idx")
    echo "$(( (val % max) + offset ))"
}

# --- DIE STADT (AWK GENERIERT) ---
# Erzeugt die Skyline effizient in einem Block
draw_city() {
    awk -v h=$H -v w=$W -v esc="$E" 'BEGIN {
        srand();
        for (x=1; x<=w; x++) {
            if (x > col_next) {
                bw = int(rand()*6) + 4; bh = int(rand()*5) + 3;
                for (i=0; i<bw; i++) {
                    if (x+i <= w) {
                        heights[x+i] = bh;
                        for (j=0; j<bh; j++) windows[x+i,j] = (rand() > 0.8) ? 1 : 0;
                    }
                }
                col_next = x + bw;
            }
        }
        for (y=0; y<8; y++) {
            printf esc "[" (h-y) ";1H" esc "[0;37m";
            for (x=1; x<=w; x++) {
                if (y < heights[x]) {
                    if (y == heights[x]-1) printf "▀";
                    else if (windows[x,y] == 1) printf esc "[1;33m." esc "[0;37m";
                    else printf "█";
                } else printf " ";
            }
        }
    }'
}

# --- FUNKELN NACH DER EXPLOSION ---
post_sparkle() {
    local y=$1 x=$2
    local i=0
    # 4 mal kurzes Aufblitzen an verschiedenen Stellen
    while [ $i -lt 4 ]; do
         local sc=$((31 + (i%7))) # Wechselnde Farbe
         case $((i%2)) in
            0) printf "${E}[1;${sc}m${E}[$((y-1));$((x+1))H.${E}[$((y+2));$((x-2))H." ;;
            1) printf "${E}[1;${sc}m${E}[$((y+1));$((x+2))H.${E}[$((y-2));$((x-1))H." ;;
         esac
         usleep 50000
         # Die kleinen Funken wieder löschen
         printf "${E}[$((y-1));$((x+1))H ${E}[$((y+2));$((x-2))H ${E}[$((y+1));$((x+2))H ${E}[$((y-2));$((x-1))H "
         i=$((i+1))
    done
}

# --- DYNAMISCHE RAKETE MIT WOBBLE ---
# $1=Start-X, $2=Ziel-Y, $3=Geschwindigkeit
rocket() {
    local start_x=$1 target=$2 speed=$3
    local color=$((31 + (start_x % 7)))
    local cur_x=$start_x
    
    # Aufstieg mit Zick-Zack
    for y in $(seq $((H-8)) -1 $target); do
        # Wobble berechnen (-1, 0 oder +1 je nach Höhe)
        local wobble=$(( (y % 3) - 1 ))
        cur_x=$((cur_x + wobble))
        # Verhindern, dass sie aus dem Bild fliegt
        [ $cur_x -lt 2 ] && cur_x=2
        [ $cur_x -gt $((W-2)) ] && cur_x=$((W-2))

        printf "${E}[1;${color}m${E}[${y};${cur_x}H^"
        usleep "$speed"
        printf "${E}[${y};${cur_x}H "
    done
    
    # Explosion an der letzten Position (cur_x)
    printf "${E}[1;${color}m"
    printf "${E}[${target};${cur_x}H*${E}[$((target-1));${cur_x}H+${E}[$((target+1));${cur_x}H+${E}[${target};$((cur_x-2))H+${E}[${target};$((cur_x+2))H+"
    usleep 50000
    printf "${E}[$((target-2));$((cur_x-1))H.${E}[$((target-2));$((cur_x+1))H.${E}[$((target+2));$((cur_x-1))H.${E}[$((target+2));$((cur_x+1))H."
    usleep 60000
    
    # Das Nachglühen
    post_sparkle "$target" "$cur_x"

    # Endgültiges Aufräumen des Himmelsbereiches
    local r; for r in -3 -2 -1 0 1 2 3; do
        [ $((target+r)) -lt $((H-8)) ] && printf "${E}[$((target+r));$((cur_x-4))H         "
    done
}

# --- START DER SHOW ---
draw_city
usleep 800000

# Finale Salve: Viele Raketen, parallel, unterschiedlich schnell
idx=1
while [ $idx -lt 35 ]; do
    # Koordinaten aus dem Pool
    rx=$(get_num $idx $((W-10)) 5)
    ry=$(get_num $((idx+100)) 10 3) # Zielhöhe variieren
    # Geschwindigkeit variabel (schnell bis mittel)
    rspeed=$(get_num $((idx+200)) 25001 15000)
    
    # Start im Hintergrund
    rocket "$rx" "$ry" "$rspeed" &
    
    idx=$((idx + 1))
    # Zufällige Wartezeit bis zum nächsten Start
    rwait=$(get_num $((idx+300)) 100001 30000)
    usleep "$rwait"
done

wait # Warten auf das letzte Funkeln
sleep 1 # Kurze Pause vor dem Text
printf "${E}[2J"

# --- FINALE: ASCII ART 2026 ---
X_OFF=$(( (W/2) - 20 )); Y_OFF=$(( (H/2) - 4 ))
[ $X_OFF -lt 1 ] && X_OFF=1
printf "${E}[1;33m" # Goldene Farbe
printf "${E}[$((Y_OFF+0));${X_OFF}H  ████   ████   ████   ████  "
printf "${E}[$((Y_OFF+1));${X_OFF}H      █ █    █      █ █      "
printf "${E}[$((Y_OFF+2));${X_OFF}H  ████  █    █  ████  █████  "
printf "${E}[$((Y_OFF+3));${X_OFF}H █      █    █ █      █    █ "
printf "${E}[$((Y_OFF+4));${X_OFF}H  ████   ████   ████   ████  "

MSG="Admon wishes you a great start into the new year 2026!"
M_OFF=$(( (W/2) - (${#MSG}/2) ))
# Grüne Nachricht
printf "${E}[$((Y_OFF+7));${M_OFF}H${E}[1;32m${MSG}${E}[0m\n\n"

# Cursor wieder einschalten
printf "${E}[?25h"
