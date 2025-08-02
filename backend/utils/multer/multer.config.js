const multer = require("multer");

const storage = multer.memoryStorage(); // or configure diskStorage as needed

const upload = multer({ storage });

module.exports = upload;
