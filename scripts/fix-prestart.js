const fs = require("fs");
const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
pkg.scripts.prestart =
  "node -e \"const fs=require('fs'); fs.copyFileSync('./data/database-seed.json','./data/database.json');\"";
fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2));
console.log("prestart script updated successfully");
console.log("New prestart:", pkg.scripts.prestart);