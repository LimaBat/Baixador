"""Transforma o Baixador.bat em build/Baixador.py (Python puro) para o PyInstaller gerar o Baixador.exe.

A primeira linha do .bat é do lote do Windows; aqui ela vira comentário. Se a variável VERSAO estiver definida
(a tag da Release, por exemplo v3.2), o número de versão dentro do programa passa a ser esse, para o aviso
de atualização funcionar.
"""
import os
import re
import sys

raiz = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
with open(os.path.join(raiz, "Baixador.bat"), encoding="utf-8") as f:
    fonte = f.read().replace("\r\n", "\n")

versao = (os.environ.get("VERSAO") or "").strip().lstrip("vV")
if versao:
    if not re.fullmatch(r"\d+(\.\d+){0,3}", versao):
        sys.exit(f"Tag inválida: {versao!r} (use algo como v3.2)")
    fonte, n = re.subn(r'^VERSAO = "[^"]*"', f'VERSAO = "{versao}"', fonte, count=1, flags=re.M)
    if n != 1:
        sys.exit("Não achei a linha VERSAO no Baixador.bat")

os.makedirs(os.path.join(raiz, "build"), exist_ok=True)
saida = os.path.join(raiz, "build", "Baixador.py")
with open(saida, "w", encoding="utf-8", newline="\n") as f:
    f.write("# " + fonte)
compile("# " + fonte, saida, "exec")
print("Pronto:", saida, "versão", versao or "(a do arquivo)")
