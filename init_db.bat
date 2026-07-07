@echo off
set /p MYSQL_PASS=Enter MySQL root password (leave blank if none): 

echo Initializing database schema...
mysql -u root -p"%MYSQL_PASS%" < sql\01_schema.sql

echo Seeding database...
mysql -u root -p"%MYSQL_PASS%" portfolio_db < sql\02_seed.sql

echo Creating views...
mysql -u root -p"%MYSQL_PASS%" portfolio_db < sql\04_views.sql

echo Creating triggers...
mysql -u root -p"%MYSQL_PASS%" portfolio_db < sql\05_triggers.sql

echo Creating cursors/stored procedures...
mysql -u root -p"%MYSQL_PASS%" portfolio_db < sql\06_cursors.sql

echo Database initialized successfully!
pause
