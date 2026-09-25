@echo off
set "MYSQL_PASS="
set /p MYSQL_PASS=Enter MySQL root password (leave blank if none): 
set "PASS_ARG="
if defined MYSQL_PASS set PASS_ARG=-p"%MYSQL_PASS%"

echo Initializing database schema...
mysql -u root %PASS_ARG% < sql\01_schema.sql

echo Seeding database...
mysql -u root %PASS_ARG% portfolio_db < sql\02_seed.sql

echo Creating views...
mysql -u root %PASS_ARG% portfolio_db < sql\04_views.sql

echo Creating triggers...
mysql -u root %PASS_ARG% portfolio_db < sql\05_triggers.sql

echo Creating cursors/stored procedures...
mysql -u root %PASS_ARG% portfolio_db < sql\06_cursors.sql

echo Database initialized successfully!
pause
