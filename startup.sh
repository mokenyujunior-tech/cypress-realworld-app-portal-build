#!/bin/bash
cd /home/site/wwwroot
node -e "const fs=require('fs'); fs.copyFileSync('./data/database-seed.json','./data/database.json');"
node_modules/.bin/ts-node -P tsconfig.tsnode.json -r tsconfig-paths/register backend/app.ts