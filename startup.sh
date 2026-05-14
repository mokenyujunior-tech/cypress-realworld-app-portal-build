#!/bin/bash
cd /home/site/wwwroot

echo "Seeding database..."
node -e "const fs=require('fs'); fs.copyFileSync('./data/database-seed.json','./data/database.json');"

echo "Waiting for node_modules to be ready..."
while [ ! -f node_modules/.bin/ts-node ]; do
  echo "Still waiting..."
  sleep 2
done

echo "Starting application..."
node_modules/.bin/ts-node -P tsconfig.tsnode.json -r tsconfig-paths/register backend/app.ts