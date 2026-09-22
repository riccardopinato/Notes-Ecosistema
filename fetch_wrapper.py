"""Recover official wrapper matching this project's Gradle properties."""
from pathlib import Path
from urllib.request import urlopen
import hashlib, re
root=Path(__file__).resolve().parents[1]
props=root/"gradle/wrapper/gradle-wrapper.properties"
config=props.read_text(encoding="utf-8-sig")
version=re.search(r"gradle-([0-9.]+)-bin.zip",config).group(1)
def fetch(url):
    with urlopen(url,timeout=30) as response: return response.read()
base=f"https://services.gradle.org/distributions/gradle-{version}"
jar=fetch(f"https://raw.githubusercontent.com/gradle/gradle/v{version}/gradle/wrapper/gradle-wrapper.jar")
expected=fetch(base+"-wrapper.jar.sha256").decode().strip()
assert hashlib.sha256(jar).hexdigest()==expected
(root/"gradle/wrapper/gradle-wrapper.jar").write_bytes(jar)
for name in ("gradlew","gradlew.bat"):
    (root/name).write_bytes(fetch(f"https://raw.githubusercontent.com/gradle/gradle/v{version}/{name}"))
digest=fetch(base+"-bin.zip.sha256").decode().strip()
config=re.sub(r"(?m)^distributionSha256Sum=.*\n?","",config)
props.write_text(config.rstrip()+"\ndistributionSha256Sum="+digest+"\n",encoding="utf-8")
(root/"docs/wrapper-verification.txt").write_text(f"Gradle {version}\nWrapper SHA-256: {expected}\nDistribution SHA-256: {digest}\n",encoding="utf-8")
print(f"Gradle {version} wrapper verified")
