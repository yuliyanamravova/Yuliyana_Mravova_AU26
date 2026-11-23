-- ----------------Task 2--------------------------------
--1. Create table ‘table_to_delete’ and fill it with the following query:

CREATE TABLE table_to_delete AS
SELECT 'veeeeeeery_long_string' || x AS col
FROM generate_series(1,(10^7)::int) x; -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)


--2. Lookup how much space this table consumes with the following query:


               SELECT *, pg_size_pretty(total_bytes) AS total,
                                    pg_size_pretty(index_bytes) AS INDEX,
                                    pg_size_pretty(toast_bytes) AS toast,
                                    pg_size_pretty(table_bytes) AS TABLE
               FROM ( SELECT *, total_bytes-index_bytes-COALESCE(toast_bytes,0) AS table_bytes
                               FROM (SELECT c.oid,nspname AS table_schema,
                                                               relname AS TABLE_NAME,
                                                              c.reltuples AS row_estimate,
                                                              pg_total_relation_size(c.oid) AS total_bytes,
                                                              pg_indexes_size(c.oid) AS index_bytes,
                                                              pg_total_relation_size(reltoastrelid) AS toast_bytes
                                              FROM pg_class c
                                              LEFT JOIN pg_namespace n ON n.oid = c.relnamespace
                                              WHERE relkind = 'r'
                                              ) a
                                    ) a
               WHERE table_name LIKE '%table_to_delete%';
               
/*
oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total |index  |toast     |table |
-----+------------+---------------+------------+-----------+-----------+-----------+-----------+------+-------+----------+------+
57345|public      |table_to_delete|        -1.0|  602488832|          0|       8192|  602480640|575 MB|0 bytes|8192 bytes|575 MB|*/

--3. Issue the following DELETE operation on ‘table_to_delete’:

   DELETE FROM table_to_delete
   WHERE REPLACE(col, 'veeeeeeery_long_string','')::int % 3 = 0; -- removes 1/3 of all rows


/*a) Note how much time it takes to perform this DELETE statement; - Execute time - 7.898s
  b) Lookup how much space this table consumes after previous DELETE;
		oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total |index  |toast     |table |
		-----+------------+---------------+------------+-----------+-----------+-----------+-----------+------+-------+----------+------+
		57345|public      |table_to_delete|    10000563|  602611712|          0|       8192|  602603520|575 MB|0 bytes|8192 bytes|575 MB|
  c) Perform the following command (if you're using DBeaver, press Ctrl+Shift+O to observe server output (VACUUM results)):
  		vacuuming "public.table_to_delete"
		"public.table_to_delete": found 0 removable, 6666667 nonremovable row versions in 73536 pages*/ 
	VACUUM FULL VERBOSE table_to_delete;
/*d) Check space consumption of the table once again and make conclusions;
		oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total |index  |toast     |table |
		-----+------------+---------------+------------+-----------+-----------+-----------+-----------+------+-------+----------+------+
		57345|public      |table_to_delete|   6666667.0|  401580032|          0|       8192|  401571840|383 MB|0 bytes|8192 bytes|383 MB|
  e) Recreate ‘table_to_delete’ table;*/
	CREATE TABLE table_to_delete AS
	SELECT 'veeeeeeery_long_string' || x AS col
	FROM generate_series(1,(10^7)::int) x; -- generate_series() creates 10^7 rows of sequential numbers from 1 to 10000000 (10^7)


--4. Issue the following TRUNCATE operation: 
TRUNCATE table_to_delete;
/*a) Note how much time it takes to perform this TRUNCATE statement. - Execute time	- 0.27s
  b) Compare with previous results and make conclusion. - The TRUNCATE statement is executed hundred times faster
  c) Check space consumption of the table once again and make conclusions; 
oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total     |index  |toast     |table  |
-----+------------+---------------+------------+-----------+-----------+-----------+-----------+----------+-------+----------+-------+
57345|public      |table_to_delete|        -1.0|       8192|          0|       8192|          0|8192 bytes|0 bytes|8192 bytes|0 bytes|
      */


/*5. Hand over your investigation's results to your mentor. The results must include:
a) Space consumption of ‘table_to_delete’ table before and after each operation;

1.First create - 575 MB
oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total |index  |toast     |table |
-----+------------+---------------+------------+-----------+-----------+-----------+-----------+------+-------+----------+------+
57345|public      |table_to_delete|        -1.0|  602488832|          0|       8192|  602480640|575 MB|0 bytes|8192 bytes|575 MB|

2.Delete - 575 MB
oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total |index  |toast     |table |
-----+------------+---------------+------------+-----------+-----------+-----------+-----------+------+-------+----------+------+
57345|public      |table_to_delete|    10000563|  602611712|          0|       8192|  602603520|575 MB|0 bytes|8192 bytes|575 MB|

3.Vacuum - 383 MB
oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total |index  |toast     |table |
-----+------------+---------------+------------+-----------+-----------+-----------+-----------+------+-------+----------+------+
57345|public      |table_to_delete|   6666667.0|  401580032|          0|       8192|  401571840|383 MB|0 bytes|8192 bytes|383 MB|

4.Truncate - 0 bytes
oid  |table_schema|table_name     |row_estimate|total_bytes|index_bytes|toast_bytes|table_bytes|total     |index  |toast     |table  |
-----+------------+---------------+------------+-----------+-----------+-----------+-----------+----------+-------+----------+-------+
57345|public      |table_to_delete|        -1.0|       8192|          0|       8192|          0|8192 bytes|0 bytes|8192 bytes|0 bytes|

b) Compare DELETE and TRUNCATE in terms of:
	-execution time: DELETE is slow, it scans the table, checks the filters, and logs row-by-row deletion. TRUNCATE is extremely fast, it operates at the storage level without going through each row.
	-disk space usage - DELETE does not return back storage to the OS immediately. TRUNCATE reclaims disk space instantly 
	-transaction behavior - DELETE operates on individual rows inside transactions and generates Write-Ahead Logging activity. TRUNCATE locks the entire table ('ACCESS EXCLUSIVE') and avoids per-row logging
	-rollback possibility - fully rollbackable inside transaction blocks, TRUNCATE is MVCC-safe and can be rolled back if executed inside an active transaction block*/

/*
c) Explain:

 - why DELETE does not free space immediately: DELETE assigns a deleted flag to each row
 but they are not actually removed from the disk. The file size stays the same. Those dead rows are eventually 
 removed, their space is reused for new data, not returned to the OS. The table file on disk remains the same size.
 
 - why VACUUM FULL changes table size: VACUUM FULL changes the table size because it creates a new table that
 takes only live rows. The old bigger file is removed and all of the dead space is returned to the OS.
 
 - why TRUNCATE behaves differently - TRUNCATE operates on the table's structure and storage. All rows are removed 
 almost instanteniously. The operation does not process individual rows and it generates a minimum of transaction log overhead.
 It resets the identifying column of the table by default.
 
 - how these operations affect performance and storage - 
 	DELETE increases the table bloat as the freed space is not returned to the OS and scans read over 
 dead rows until auto-commit runs
 	VACUUM FULL recovers storage and returns the maximum of it to the OS but concurrent actions are
 blocked during the execution
 	TRUNCATE is the best choice of them because it clears massive datasets fast and efficiently, 
 with minimal overhead*/

