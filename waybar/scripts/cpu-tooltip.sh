#!/bin/bash

# per-core CPU usage graph for Waybar.
#
# CPU usage calculation adapted from Paul Colby's
# "Linux CPU usage from /proc/stat":
# https://colby.id.au/calculating-cpu-usage-from-proc-stat/
#
# adapted for per-core Waybar output.

icons=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
printf '{"text":"cpu 0%% ","tooltip":""}\n'

declare -a prev_total prev_idle

while sleep 1; do
    graph=""

    while read -r cpu user nice system idle iowait irq softirq steal _; do
        [[ $cpu =~ ^cpu[0-9]+$ ]] || continue

        total=$((user + nice + system + idle + iowait + irq + softirq + steal))
        idle=$((idle + iowait))
        n=${cpu#cpu}

        if [[ -n ${prev_total[n]} ]]; then
            diff_total=$((total - prev_total[n]))
            diff_idle=$((idle - prev_idle[n]))

            usage=$((100 * (diff_total - diff_idle) / diff_total))
            ((usage < 0)) && usage=0
            ((usage > 100)) && usage=100

            graph+=${icons[$((usage * 7 / 100))]}
        fi

        prev_total[n]=$total
        prev_idle[n]=$idle
    done < /proc/stat

    # Source: https://superuser.com
    cpu_total=$(awk '{u=$2+$4; t=$2+$4+$5; if (NR==1){u1=u; t1=t} else print int(($2+$4-u1)*100/(t-t1)) "%"}' <(grep 'cpu ' /proc/stat) <(sleep 1; grep 'cpu ' /proc/stat))

    printf '{"text":"cpu %s ","tooltip":"%s"}\n' "$cpu_total" "$graph"
done
