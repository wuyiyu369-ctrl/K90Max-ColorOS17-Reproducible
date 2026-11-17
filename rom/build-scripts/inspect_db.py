import sqlite3
p=r'C:\Users\USERNAME\Documents\Codex\2026-10-08\wo\modules_config.db'
c=sqlite3.connect(p)
print(c.execute("select name,sql from sqlite_master where type='table'").fetchall())
for (n,) in c.execute("select name from sqlite_master where type='table'"):
 print('TABLE',n)
 print(c.execute(f'pragma table_info({n})').fetchall())
 print(c.execute(f'select * from {n} limit 30').fetchall())
