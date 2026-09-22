"""Host SQL checks only: no Kotlin compilation or Room code generation."""
from pathlib import Path
import sqlite3, re
from xml.etree import ElementTree
root=Path(__file__).resolve().parents[1]
for p in (root/"app/src/main").rglob("*.xml"): ElementTree.parse(p)
source=(root/"app/src/main/java/it/notes/ecosystem/data/NotesDatabase.kt").read_text(encoding="utf-8-sig")
migration=re.search(r'db.execSQL\("([^"]+)"\)',source).group(1)
queries=dict((name,sql) for sql,name in re.findall(r'@Query\("([^"]+)"\)\s+(?:suspend\s+)?fun\s+(\w+)',source))
db=sqlite3.connect(":memory:")
db.executescript("""
CREATE TABLE collections(id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL UNIQUE);
CREATE TABLE notes(id TEXT PRIMARY KEY NOT NULL,title TEXT NOT NULL,body TEXT NOT NULL,collectionId TEXT,favorite INTEGER NOT NULL,createdAt INTEGER NOT NULL,updatedAt INTEGER NOT NULL,deletedAt INTEGER);
INSERT INTO notes VALUES('a','Originale','Caffè',NULL,1,1,2,NULL);
""")
before=db.execute("SELECT * FROM notes").fetchall()
db.execute(migration)
assert db.execute("SELECT * FROM notes").fetchall()==before
db.execute("INSERT INTO drafts VALUES('a','Bozza','Righe\nUnicode è',NULL,3)")
db.commit()
db.execute("BEGIN")
db.execute("UPDATE notes SET body='Salvata' WHERE id='a'")
db.execute(queries["deleteDraft"],{"id":"a"})
db.rollback()
assert db.execute(queries["getDraft"],{"id":"a"}).fetchone()[2]=="Righe\nUnicode è"
assert db.execute(queries["get"],{"id":"a"}).fetchone()[2]=="Caffè"
db.execute(queries["deleteDraft"],{"id":"a"})
assert db.execute(queries["getDraft"],{"id":"a"}).fetchone() is None
assert db.execute("SELECT * FROM notes").fetchall()==before
for name in ("observeDrafts","allDrafts","allNotes","allCollections","observeNotes","observeCollections"):
    db.execute(queries[name]).fetchall()
db.close()
result="PASS: XML validi\nPASS: SQL migrazione preserva note v1\nPASS: rollback conserva nota e bozza\nPASS: scarto bozza non altera nota\nPASS: query snapshot e liste valide\nLIMIT: compilazione Kotlin, Room e test Android non eseguiti.\n"
(root/"docs/host-checks.txt").write_text(result,encoding="utf-8")
print(result)
