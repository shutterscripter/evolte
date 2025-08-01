const mysql = require("mysql");

/** create connection to SQL DATABASE **/
let connection = mysql.createConnection({
  host: "db",
  user: "root",
  password: "root",
  database: "myoffice",
});

// const connection = mysql.createConnection({
//     host: "localhost",
//     user: "sunshineiot_sangam_dev",
//     password: "ZdCQ8erzv[he",
//     database: "sunshineiot_myoffice",

// });

module.exports = connection;
