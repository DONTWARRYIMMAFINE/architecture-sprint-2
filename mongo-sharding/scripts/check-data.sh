#!/bin/bash

###
# Проверяем данные на первом шарде
###
echo -n "Documents in shard1: "
docker compose exec -T shard1 mongosh --port 27018 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments();" | tail -n 1

###
# Проверяем данные на втором шарде
###
echo -n "Documents in shard2: "
docker compose exec -T shard2 mongosh --port 27019 --quiet --eval "db.getSiblingDB('somedb').helloDoc.countDocuments();" | tail -n 1
