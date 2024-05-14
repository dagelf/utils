currentline=$(pactl list short sinks | grep -n "$(pactl get-default-sink)" | cut -d: -f 1)
lastline=$(pactl list short sinks | wc -l)
nextline=$(($currentline % $lastline + 1))
nextsink=$(pactl list short sinks | head "-n$nextline" | tail -1 | cut -f 1)

pactl set-default-sink $nextsink

for sinkinput in $(pactl list short sink-inputs | cut -f 1); do
  pactl move-sink-input $sinkinput "@DEFAULT_SINK@"
done
