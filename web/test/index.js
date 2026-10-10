// `node --test web/test/` names this folder, and Node 22 and later run a folder named that way as a module: this
// file. It loads every *.test.js beside it, so the command runs the whole suite (Node 20 searched the folder itself).
// When the test runner finds this file on its own (`node --test` with a glob, or with no arguments), it does nothing,
// so no test runs twice.
'use strict';

const fs = require('fs');
const path = require('path');

if (path.resolve(process.argv[1] || '') === __dirname) {
  for (const file of fs.readdirSync(__dirname).filter((f) => f.endsWith('.test.js')).sort()) {
    require(path.join(__dirname, file));
  }
}
