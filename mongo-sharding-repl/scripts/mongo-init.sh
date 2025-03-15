#!/bin/bash

###
# Утилитарная функция, которая оборачивает вызов команды и добавляет статус по завершению
###
execute_command() {
  local description="$1"
  shift
  echo -n "$description..."
  if "$@" &>/dev/null; then
    echo " ОК"
  else
    echo " FAIL"
    exit 1
  fi
}

###
# Утилитарная функция, помогает дождать полной инициализации сервиса
###
wait_for_mongo() {
  local host=$1
  local port=$2
  echo -n "Waiting for MongoDB at $host:$port..."
  until docker compose exec -T "$host" mongosh --port "$port" --quiet --eval "db.runCommand('ping').ok" &>/dev/null; do
    sleep 2
  done
  echo -e "\rWaiting for MongoDB at $host:$port... ОК"
}

###
# Инициализируем сервисы конфигурации
###
execute_command "Initializing configuration services" docker compose exec -T configSrv1 mongosh --quiet --port 27016 <<EOF
rs.initiate({
  _id : "config_server",
  configsvr: true,
  members: [
    { _id: 0, host: "configSrv1:27016" },
    { _id: 1, host: "configSrv2:27017" }
  ]
});
EOF

###
# Инициализируем шарды
###
execute_command "Initializing shard1" docker compose exec -T shard1_1 mongosh --quiet --port 27018 <<EOF
rs.initiate({
  _id : "shard1",
  members: [
    { _id: 0, host: "shard1_1:27018" },
    { _id: 1, host: "shard1_2:27019" },
    { _id: 2, host: "shard1_3:27020" }
  ]
});
EOF

execute_command "Initializing shard2" docker compose exec -T shard2_1 mongosh --quiet --port 27021 <<EOF
rs.initiate({
  _id : "shard2",
  members: [
    { _id: 0, host: "shard2_1:27021" },
    { _id: 1, host: "shard2_2:27022" },
    { _id: 2, host: "shard2_3:27023" }
  ]
});
EOF

###
# Инициализируем роутеры (достаточно сделать на одном, второй синхронизируется через configSrv)
###
wait_for_mongo mongos_router1 27024
execute_command "Initializing mongos_router1" docker compose exec -T mongos_router1 mongosh --quiet --port 27024 <<EOF
sh.addShard("shard1/shard1_1:27018,shard1_2:27019,shard1_3:27020");
sh.addShard("shard2/shard2_1:27021,shard2_2:27022,shard2_3:27023");
sh.enableSharding("somedb");
sh.shardCollection("somedb.helloDoc", { "name" : "hashed" } )
EOF

###
# Заполняем шарды данными
###
execute_command "Inserting data" docker compose exec -T mongos_router1 mongosh --quiet --port 27024 <<EOF
use somedb
for(var i = 0; i < 1000; i++) db.helloDoc.insertOne({age:i, name:"ly"+i})
EOF

###
# Проверяем количество данных (уже через другой роутер)
###
echo -n "Checking data... "
docker compose exec -T mongos_router2 mongosh --quiet --port 27025 --eval "db.getSiblingDB('somedb').helloDoc.countDocuments();" | tail -n 1
