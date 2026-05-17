const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.scripts.prestart =
  "node -e \"const fs=require('fs'); fs.copyFileSync('./data/database-seed.json','./data/database.json');\"";
pkg.scripts.start =
  "ts-node -P tsconfig.tsnode.json -r tsconfig-paths/register backend/app.ts";
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2));
console.log("Scripts updated successfully");
console.log("New prestart:", pkg.scripts.prestart);
console.log("New start:", pkg.scripts.start);