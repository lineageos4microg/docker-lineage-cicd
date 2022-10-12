import subprocess

def build() -> None:
    subprocess.run(["/root/build.sh"], check=True, stderr=subprocess.STDOUT)

if __name__ == "__main__":
    build()