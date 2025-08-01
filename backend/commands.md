## Access the MySQL container’s shell:

```bash
docker exec -it backend-db-1 bash
```

## Log in to MySQL:

```bash
mysql -u root -p
```

(Enter "root" as the password when prompted.)

## Select your database:

```sql
USE myoffice;
```

## Create your table:

```sql
CREATE TABLE users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(255) NOT NULL UNIQUE,
  otp CHAR(4) NOT NULL,
  otp_created TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```
