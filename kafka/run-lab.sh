#!/usr/bin/env bash
# Kafka lab: keys and partitions, consumer groups, lag, and consumer scaling.
# Needs Docker. Runs a single local broker, prints the results, then removes it.
set -euo pipefail

BROKER=localhost:9092
k() { docker exec -i kafka /opt/kafka/bin/"$@"; }
produce() { k kafka-console-producer.sh --bootstrap-server "$BROKER" --topic trades \
  --property parse.key=true --property key.separator=: 2>/dev/null; }
lag() { k kafka-consumer-groups.sh --bootstrap-server "$BROKER" --describe --group "$1" 2>/dev/null; }

echo "== Starting a single Kafka broker"
docker rm -f kafka >/dev/null 2>&1 || true
docker run -d --name kafka -p 9092:9092 apache/kafka:latest >/dev/null
sleep 20

echo "== Creating topic 'trades' with 3 partitions"
k kafka-topics.sh --bootstrap-server "$BROKER" --create --topic trades --partitions 3 --replication-factor 1

echo "== 1. Three bond keys: which partitions do they land in?"
for i in $(seq 1 30); do echo "BOND-$((i % 3)):trade $i"; done | produce
k kafka-console-consumer.sh --bootstrap-server "$BROKER" --topic trades --group risk \
  --from-beginning --max-messages 30 --property print.partition=true --property print.key=true 2>/dev/null \
  | awk '{print $1, $2}' | sort | uniq -c

echo "== 2. 300 more trades while 'risk' is not reading: lag grows"
for i in $(seq 31 330); do echo "BOND-$((i % 3)):trade $i"; done | produce
lag risk

echo "== 3. A second group 'reporting' reads everything: its own bookmarks"
k kafka-console-consumer.sh --bootstrap-server "$BROKER" --topic trades --group reporting \
  --from-beginning --max-messages 330 >/dev/null 2>&1
lag reporting

echo "== 4. 'risk' catches up from its bookmark: lag back to 0"
k kafka-console-consumer.sh --bootstrap-server "$BROKER" --topic trades --group risk \
  --max-messages 300 >/dev/null 2>&1
lag risk

echo "== 5. Four consumers on three partitions: one sits idle"
for n in 1 2 3 4; do
  docker exec -d kafka /opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server "$BROKER" \
    --topic trades --group scale --timeout-ms 60000
done
sleep 20
k kafka-consumer-groups.sh --bootstrap-server "$BROKER" --describe --group scale --members 2>/dev/null

echo "== Cleaning up"
docker rm -f kafka >/dev/null