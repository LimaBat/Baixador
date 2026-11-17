@echo off & goto :BXBAT_INICIO
r'''
:BXBAT_INICIO
setlocal EnableExtensions DisableDelayedExpansion
title Baixador
set "BX_APP=%~f0"
set "PYTHONUTF8=1"
call :BXBAT_ACHAR
if defined BX_PY goto :BXBAT_ABRIR
echo.
echo  ===================================================
echo    BAIXADOR - preparando o computador
echo  ===================================================
echo.
echo  O Python 3 nao foi encontrado neste computador.
echo  Vou instalar agora (so na primeira vez, pode levar
echo  alguns minutos). Nao feche esta janela.
echo.
call :BXBAT_WINGET
call :BXBAT_ACHAR
if defined BX_PY goto :BXBAT_ABRIR
call :BXBAT_BAIXAR
call :BXBAT_ACHAR
if defined BX_PY goto :BXBAT_ABRIR
echo.
echo  Nao consegui instalar o Python automaticamente.
echo  Instale manualmente em https://www.python.org/downloads/
echo  (marque "Add python.exe to PATH") e abra este arquivo de novo.
echo.
pause
exit /b 1

:BXBAT_ABRIR
set "BX_PYW="
if "%BX_PY%"=="py -3" set "BX_PYW=pyw -3"
if "%BX_PY%"=="python" set "BX_PYW=pythonw"
if not defined BX_PYW call :BXBAT_PYWX %BX_PY%
if not defined BX_PYW goto :BXBAT_CONSOLE
start "" %BX_PYW% -x "%BX_APP%" %*
exit /b 0

:BXBAT_CONSOLE
echo  Abrindo o Baixador...
%BX_PY% -x "%BX_APP%" --iniciar %*
exit /b 0

:BXBAT_PYWX
if exist "%~dp1pythonw.exe" set BX_PYW="%~dp1pythonw.exe"
exit /b 0

:BXBAT_ACHAR
set "BX_PY="
call :BXBAT_TESTA py -3
call :BXBAT_TESTA python
for /d %%D in ("%LOCALAPPDATA%\Programs\Python\Python3*") do call :BXBAT_TESTA "%%~D\python.exe"
for /d %%D in ("%ProgramFiles%\Python3*") do call :BXBAT_TESTA "%%~D\python.exe"
for /d %%D in ("%LOCALAPPDATA%\Python\pythoncore-3*") do call :BXBAT_TESTA "%%~D\python.exe"
call :BXBAT_TESTA "%LOCALAPPDATA%\Programs\Python\Launcher\py.exe" -3
exit /b 0

:BXBAT_TESTA
if defined BX_PY exit /b 0
%* -c "import sys;sys.exit(0 if sys.version_info>=(3,9) else 1)" >nul 2>&1
if errorlevel 1 exit /b 0
set BX_PY=%*
exit /b 0

:BXBAT_WINGET
where winget >nul 2>&1
if errorlevel 1 exit /b 0
echo  [1/2] Instalando o Python 3.13 pelo winget...
winget install -e --id Python.Python.3.13 --scope user --silent --accept-package-agreements --accept-source-agreements
exit /b 0

:BXBAT_BAIXAR
echo  [1/2] Baixando o instalador do Python (python.org)...
set "BX_INST=%TEMP%\python_instalador_baixador.exe"
del "%BX_INST%" >nul 2>&1
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue';[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12;foreach($v in @('3.13.5','3.12.10')){try{Invoke-WebRequest -UseBasicParsing -Uri ('https://www.python.org/ftp/python/'+$v+'/python-'+$v+'-amd64.exe') -OutFile $env:BX_INST;break}catch{}}"
if not exist "%BX_INST%" exit /b 0
echo  [2/2] Instalando o Python (nao precisa de administrador)...
start "" /wait "%BX_INST%" /quiet InstallAllUsers=0 InstallLauncherAllUsers=0 PrependPath=1 Include_launcher=1 Include_test=0
del "%BX_INST%" >nul 2>&1
exit /b 0
'''
# BAIXADOR - músicas, vídeos e fontes (programa em arquivo único).
# Roda de dois jeitos: como Baixador.bat (o trecho em lote acima acha ou instala o Python e roda este arquivo
# com "python -x") ou como Baixador.exe, que o próprio programa gera com o PyInstaller na primeira vez que abre.
# A janela é própria (pywebview + WebView2); sem ele, usa o Edge em modo aplicativo.
# Tudo fica em %LOCALAPPDATA%\Baixador (o aplicativo em %LOCALAPPDATA%\Baixador\app\Baixador.exe).
import os, sys, subprocess

CONGELADO = bool(getattr(sys, "frozen", False))   # True no Baixador.exe
ARQ_PROG = os.path.abspath(sys.executable if CONGELADO else __file__)
_AQUI = os.path.dirname(ARQ_PROG)
sys.path[:] = [p for p in sys.path if p and os.path.normcase(os.path.abspath(p)) != os.path.normcase(_AQUI)]

if "--iniciar" in sys.argv and not CONGELADO:   # aberto com python.exe: relança com pythonw.exe (sem janela preta)
    sys.argv.remove("--iniciar")
    _w = os.path.join(os.path.dirname(sys.executable or ""), "pythonw.exe")
    if os.name == "nt" and os.path.exists(_w):
        try:
            subprocess.Popen([_w, "-x", ARQ_PROG] + sys.argv[1:], close_fds=True,
                             creationflags=0x00000008 | 0x00000200)
            sys.exit(0)
        except OSError:
            pass

import ctypes, glob, hashlib, html, io, json, queue, re, secrets, shutil, socket, threading, time
import traceback, urllib.parse, urllib.request, webbrowser, zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

VERSAO = "3.1"
REPO = "LimaBat/baixador"          # repositório do código; as Releases têm o Baixador.exe
NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)
DEMO = "--demo" in sys.argv          # só para testar a tela sem internet

if os.name == "nt":
    BASE = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.expanduser("~"), "Baixador")
    try:
        ctypes.windll.kernel32.SetErrorMode(0x0001 | 0x8000)   # sem aviso "não há disco"
    except Exception:
        pass
else:
    BASE = os.path.join(os.path.expanduser("~"), ".baixador")
os.makedirs(BASE, exist_ok=True)
LIBS = os.path.join(BASE, "libs")      # yt-dlp mais novo que o de dentro do .exe (baixado do PyPI)
if CONGELADO and os.path.isdir(os.path.join(LIBS, "yt_dlp")):
    sys.path.insert(0, LIBS)

CONFIG = os.path.join(BASE, "config.json")
INST_PATH = os.path.join(BASE, "instancia.json")
LOG_PATH = os.path.join(BASE, "baixador_log.txt")
ICONE = os.path.join(BASE, "baixador-v3.ico")
PASTA_APP = os.path.join(BASE, "app")
EXE_APP = os.path.join(PASTA_APP, "Baixador.exe")
INFO_APP = os.path.join(PASTA_APP, "versao.json")
FONTE_PROG = os.path.join(BASE, "Baixador.bat")      # cópia do programa-fonte (usada para gerar o .exe)
PASTA_FONTES_APP = os.path.join(BASE, "fontes")
PASTA_CACHE_FONTES = os.path.join(BASE, "fontes_cache")
REGISTRO_FONTES = os.path.join(BASE, "fontes_site.json")
PASTA_FONTES_BAIXADAS = os.path.join(os.path.expanduser("~"), "Downloads", "Fontes")
PASTA_MUSICAS = os.path.join(os.path.expanduser("~"), "Music")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\[[0-9;]*m")

with open(ARQ_PROG, "rb") as _f:
    _BYTES_PROG = _f.read() if not CONGELADO else b""
    BUILD = hashlib.sha1(_BYTES_PROG or open(ARQ_PROG, "rb").read()).hexdigest()[:12]

DAFONT = "https://www.dafont.com/pt/"
FONTES_CAT_PADRAO = "theme.php?cat=405"
FONTES_BUSCA = DAFONT + "search.php?q={}&page={}"
FONTES_DOWNLOAD = "https://dl.dafont.com/dl/?f={}"
NAVEGADOR = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
                           "(KHTML, like Gecko) Chrome/130.0 Safari/537.36",
             "Accept-Language": "pt-BR,pt;q=0.9"}
PREVIA_FORMATO = ("bv*[height<=360][ext=mp4][protocol^=http]/bv*[height<=480][protocol^=http]/"
                  "18/worst[vcodec!=none][protocol^=http]")


def log(msg):
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + str(msg) + "\n")
    except Exception:
        pass


def ler_json(caminho, padrao):
    try:
        with open(caminho, encoding="utf-8") as f:
            v = json.load(f)
        return v if isinstance(v, type(padrao)) else padrao
    except Exception:
        return padrao


def gravar_json(caminho, valor):
    try:
        tmp = caminho + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(valor, f, ensure_ascii=False)
        os.replace(tmp, caminho)
    except Exception:
        log("gravar " + caminho + ": " + traceback.format_exc())


# ================================================================ estado de inicialização (tela de abertura)
ESTADO = {"msg": "Iniciando", "pct": 4, "pronto": False, "erro": "", "ffmpeg": False}


def etapa(msg, pct):
    ESTADO["msg"], ESTADO["pct"] = msg, pct


# ================================================================ logo (também vira o ícone do aplicativo)
TAMANHOS_ICO = (16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 128, 256)


def desenhar_logo(S=256):
    """Quadrado arredondado em degradê (roxo → magenta → coral) com ondas de som e seta de download.
    Cada tamanho é desenhado do zero: nos pequenos (barra de tarefas) o desenho fica mais simples e grosso."""
    from PIL import Image, ImageDraw
    G = max(S * 8, 512)
    u = G / 64.0
    cores = [(0.0, (124, 92, 255)), (0.55, (217, 70, 239)), (1.0, (255, 106, 61))]

    def cor(t):
        for (a, ca), (b, cb) in zip(cores, cores[1:]):
            if t <= b:
                k = (t - a) / (b - a)
                return tuple(round(x + (y - x) * k) for x, y in zip(ca, cb))
        return cores[-1][1]
    pequeno = Image.new("RGB", (64, 64))
    px = pequeno.load()
    for y in range(64):
        for x in range(64):
            px[x, y] = cor((x + y) / 126.0)
    grad = pequeno.resize((G, G), Image.BICUBIC).convert("RGBA")
    brilho = Image.new("L", (1, 64))
    for y in range(64):
        brilho.putpixel((0, y), max(0, int(82 * (1 - y / 32.0))))
    brilho = brilho.resize((G, G))
    grad = Image.composite(Image.new("RGBA", (G, G), (255, 255, 255, 255)), grad, brilho)
    margem = 0 if S >= 48 else (1 if S >= 24 else 0.5)          # 1 px de folga nos tamanhos pequenos
    m = margem * G / S
    mascara = Image.new("L", (G, G), 0)
    raio = 18 if S >= 48 else 15
    ImageDraw.Draw(mascara).rounded_rectangle((m, m, G - 1 - m, G - 1 - m), radius=int(raio * u), fill=255)
    out = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    out.paste(grad, (0, 0), mascara)
    tinta = Image.new("RGBA", (G, G), (0, 0, 0, 0))
    d = ImageDraw.Draw(tinta)

    def linha(pts, w, a=255):
        pts = [(x * u, y * u) for x, y in pts]
        d.line(pts, fill=(255, 255, 255, a), width=int(w * u), joint="curve")
        r = w * u / 2
        for x, y in pts:
            d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 255, a))
    if S <= 24:                       # só a seta e a base, bem grossas
        linha([(32, 12), (32, 40)], 8.5)
        linha([(22.5, 31), (32, 40.5), (41.5, 31)], 8.5)
        linha([(18, 51), (46, 51)], 7.5)
    elif S <= 48:                     # seta, base e duas ondas
        linha([(17, 23), (17, 38)], 6.4, 240)
        linha([(47, 23), (47, 38)], 6.4, 240)
        linha([(32, 12), (32, 39)], 6.8)
        linha([(25, 32.5), (32, 39.5), (39, 32.5)], 6.8)
        linha([(19, 50.5), (45, 50.5)], 6.2, 240)
    else:                             # desenho completo
        for x, y0, y1 in ((13, 28, 36), (20, 21, 40), (44, 21, 40), (51, 28, 36)):
            linha([(x, y0), (x, y1)], 4.6, 235)
        linha([(32, 13), (32, 39)], 5.2)
        linha([(26.5, 34), (32, 39.5), (37.5, 34)], 5.2)
        linha([(19, 50), (45, 50)], 4.6, 235)
    out.alpha_composite(tinta)
    return out.resize((S, S), Image.LANCZOS)


def gravar_ico(caminho):
    """Grava um .ico com um desenho próprio para cada tamanho (PNG dentro do .ico)."""
    import struct
    imagens = []
    for t in TAMANHOS_ICO:
        b = io.BytesIO()
        desenhar_logo(t).save(b, format="PNG", optimize=True)
        imagens.append((t, b.getvalue()))
    cab = struct.pack("<HHH", 0, 1, len(imagens))
    pos = 6 + 16 * len(imagens)
    dirs, dados = b"", b""
    for t, png in imagens:
        dirs += struct.pack("<BBBBHHII", t % 256, t % 256, 0, 0, 1, 32, len(png), pos)
        pos += len(png)
        dados += png
    tmp = caminho + ".tmp"
    with open(tmp, "wb") as f:
        f.write(cab + dirs + dados)
    os.replace(tmp, caminho)


def garantir_icone():
    try:
        if not os.path.exists(ICONE):
            gravar_ico(ICONE)
        return ICONE
    except Exception:
        log("ícone: " + traceback.format_exc())
        return None


# ================================================================ instalação: cópia, atalhos e o aplicativo .exe
def python_do_sistema():
    """python.exe usado para instalar componentes e gerar o .exe (no .exe, o que foi guardado na instalação)."""
    if CONGELADO:
        p = ler_config().get("python") or ""
        return p if p and os.path.exists(p) else None
    exe = sys.executable or ""
    py = os.path.join(os.path.dirname(exe), "python.exe")
    return py if os.name == "nt" and os.path.exists(py) else exe


def pastas_atalhos():
    lnks = []
    if os.name != "nt":
        return lnks
    for csidl in (0x0010, 0x0002):  # Área de Trabalho, menu Iniciar > Programas
        buf = ctypes.create_unicode_buffer(1024)
        if ctypes.windll.shell32.SHGetFolderPathW(None, csidl, None, 0, buf) == 0 and buf.value:
            lnks.append(os.path.join(buf.value, "Baixador.lnk"))
    return lnks


def criar_atalhos(forcar=False):
    """Atalhos na Área de Trabalho e no menu Iniciar: para o Baixador.exe se ele existir, senão pythonw + .bat."""
    if os.name != "nt":
        return
    lnks = pastas_atalhos()
    if not lnks:
        return
    if os.path.exists(EXE_APP):
        alvo, args, ico = EXE_APP, "", EXE_APP
    else:
        pyw = os.path.join(os.path.dirname(sys.executable or ""), "pythonw.exe")
        if CONGELADO or not os.path.exists(pyw):
            return
        alvo, args, ico = pyw, f'-x "{FONTE_PROG}"', garantir_icone() or ""
    marca = os.path.join(BASE, ".atalhos.json")
    ant = ler_json(marca, {})
    if not forcar and ant.get("alvo") == alvo and ant.get("ico") == ico and all(os.path.exists(l) for l in lnks):
        return
    ps = ("$w=New-Object -ComObject WScript.Shell;foreach($p in $env:BX_LNKS.Split('|')){"
          "if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force};"
          "$s=$w.CreateShortcut($p);$s.TargetPath=$env:BX_ALVO;$s.Arguments=$env:BX_ARGS;"
          "if($env:BX_ICO){$s.IconLocation=$env:BX_ICO+',0'};$s.WorkingDirectory=$env:BX_DIR;"
          "$s.Description='Baixador: músicas, vídeos e fontes';$s.Save()}")
    try:
        r = subprocess.run(["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", ps],
                           creationflags=NO_WINDOW, timeout=60, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                           env=dict(os.environ, BX_LNKS="|".join(lnks), BX_ALVO=alvo, BX_ARGS=args, BX_ICO=ico,
                                    BX_DIR=os.path.dirname(alvo)))
        if r.returncode == 0:
            gravar_json(marca, {"alvo": alvo, "ico": ico})
            try:   # avisa o Windows para redesenhar os ícones (troca a imagem velha do atalho)
                ctypes.windll.shell32.SHChangeNotify(0x08000000, 0, None, None)
            except Exception:
                pass
        else:
            log("atalhos: " + r.stderr.decode("utf-8", "replace")[-800:])
    except Exception:
        log("atalhos: " + traceback.format_exc())


def instalar_copia():
    """Guarda o programa-fonte em %LOCALAPPDATA%\\Baixador (é dele que o .exe é gerado)."""
    if CONGELADO:
        return
    try:   # grava o que foi lido ao abrir (funciona mesmo se o .bat original sumir depois)
        if os.path.normcase(ARQ_PROG) != os.path.normcase(FONTE_PROG) and _BYTES_PROG:
            with open(FONTE_PROG + ".tmp", "wb") as f:
                f.write(_BYTES_PROG)
            os.replace(FONTE_PROG + ".tmp", FONTE_PROG)
    except Exception:
        log("cópia: " + traceback.format_exc())
    if os.name == "nt":
        salvar_config(python=python_do_sistema())


APP = {"estado": "", "msg": ""}      # "", "gerando", "pronto", "falhou"


def info_app():
    return ler_json(INFO_APP, {})


def exe_em_dia():
    return os.path.exists(EXE_APP) and info_app().get("build") == BUILD


def versao_ytdlp(py=None):
    try:
        if py:
            r = subprocess.run([py, "-c", "import yt_dlp.version as v;print(v.__version__)"], capture_output=True,
                               creationflags=NO_WINDOW, timeout=60)
            return r.stdout.decode().strip()
        import yt_dlp.version
        return yt_dlp.version.__version__
    except Exception:
        return ""


def gerar_exe(motivo=""):
    """Gera o Baixador.exe com o PyInstaller do Python do computador, em segundo plano e sem janelas."""
    if os.name != "nt" or DEMO or APP["estado"] == "gerando":
        return False
    py = python_do_sistema()
    if not py or not os.path.exists(FONTE_PROG):
        return False
    APP["estado"], APP["msg"] = "gerando", motivo
    pasta = os.path.join(BASE, "build")
    try:
        log("Gerando o Baixador.exe " + motivo)
        r = subprocess.run([py, "-m", "pip", "install", "--quiet", "--disable-pip-version-check", "-U",
                            "pyinstaller", "pywebview", "yt-dlp", "pillow"], creationflags=NO_WINDOW,
                           stdin=subprocess.DEVNULL, capture_output=True, timeout=1200)
        if r.returncode:
            raise RuntimeError("pip: " + r.stderr.decode("utf-8", "replace")[-800:])
        os.makedirs(pasta, exist_ok=True)
        with open(FONTE_PROG, encoding="utf-8") as f:
            fonte = f.read().replace("\r\n", "\n")
        fonte = "# " + fonte   # a 1ª linha (do lote) vira comentário; o resto é Python puro
        arq = os.path.join(pasta, "Baixador.py")
        with open(arq, "w", encoding="utf-8", newline="\n") as f:
            f.write(fonte)
        build_fonte = BUILD
        if CONGELADO:   # o .exe não sabe o "build" do .bat: calcula aqui
            with open(FONTE_PROG, "rb") as f:
                build_fonte = hashlib.sha1(f.read()).hexdigest()[:12]
        dist = os.path.join(pasta, "dist")
        shutil.rmtree(dist, ignore_errors=True)
        cmd = [py, "-m", "PyInstaller", "--noconfirm", "--clean", "--onefile", "--windowed", "--name", "Baixador",
               "--icon", garantir_icone() or "NONE", "--distpath", dist,
               "--workpath", os.path.join(pasta, "work"), "--specpath", pasta,
               "--collect-submodules", "yt_dlp", "--collect-all", "webview", "--hidden-import", "clr", arq]
        r = subprocess.run(cmd, creationflags=NO_WINDOW | 0x00004000, stdin=subprocess.DEVNULL,
                           capture_output=True, timeout=2400, cwd=pasta)
        novo = os.path.join(dist, "Baixador.exe")
        if r.returncode or not os.path.exists(novo):
            raise RuntimeError("pyinstaller: " + r.stderr.decode("utf-8", "replace")[-1500:])
        os.makedirs(PASTA_APP, exist_ok=True)
        if os.path.exists(EXE_APP):          # se estiver aberto, o Windows deixa renomear (não apagar)
            velho = EXE_APP + ".antigo"
            try:
                os.remove(velho)
            except OSError:
                pass
            try:
                os.replace(EXE_APP, velho)
            except OSError:
                os.rename(EXE_APP, velho)
        shutil.move(novo, EXE_APP)
        gravar_json(INFO_APP, {"build": build_fonte, "yt": versao_ytdlp(py), "data": time.time()})
        criar_atalhos(forcar=True)
        apagar_bat_da_area_de_trabalho()
        APP["estado"] = "pronto"
        log("Baixador.exe pronto em " + EXE_APP)
        return True
    except Exception:
        APP["estado"] = "falhou"
        log("gerar exe:\n" + traceback.format_exc())
        return False


def apagar_bat_da_area_de_trabalho():
    """Com o aplicativo pronto, o Baixador.bat solto na Área de Trabalho não é mais preciso (a cópia fica na pasta
    do programa). Assim ninguém abre mais a tela preta sem querer."""
    if CONGELADO or not os.path.exists(FONTE_PROG):
        return
    try:
        desk = os.path.dirname(pastas_atalhos()[0])
        if os.path.normcase(os.path.dirname(ARQ_PROG)) == os.path.normcase(desk) \
                and os.path.basename(ARQ_PROG).lower().endswith(".bat"):
            os.remove(ARQ_PROG)
            log("Removido da Área de Trabalho: " + ARQ_PROG)
    except Exception:
        log("apagar bat: " + traceback.format_exc())


def instalar_exe_baixado():
    """Quem baixou o Baixador.exe do site: guarda o programa na pasta do Baixador (app) e cria os atalhos."""
    if not CONGELADO or os.name != "nt":
        return
    try:
        if os.path.normcase(ARQ_PROG) != os.path.normcase(EXE_APP):
            os.makedirs(PASTA_APP, exist_ok=True)
            if os.path.exists(EXE_APP):
                velho = EXE_APP + ".antigo"
                try:
                    os.remove(velho)
                except OSError:
                    pass
                os.replace(EXE_APP, velho)
            shutil.copy2(ARQ_PROG, EXE_APP)
            log("Instalado em " + EXE_APP)
    except Exception:
        log("instalar exe: " + traceback.format_exc())
    criar_atalhos()


def _versao_tupla(v):
    return tuple(int(x) for x in re.findall(r"\d+", v or "")[:4]) or (0,)


ATUALIZACAO = {"versao": "", "notas": "", "url": "", "estado": "", "pct": 0}


def procurar_atualizacao():
    """Vê no GitHub se saiu uma versão nova do Baixador.exe."""
    if not CONGELADO or DEMO:
        return
    try:
        req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/releases/latest",
                                     headers=dict(NAVEGADOR, Accept="application/vnd.github+json"))
        with urllib.request.urlopen(req, timeout=20) as r:
            j = json.loads(r.read().decode("utf-8"))
        tag = j.get("tag_name") or ""
        if _versao_tupla(tag) <= _versao_tupla(VERSAO):
            return
        url = next((a["browser_download_url"] for a in j.get("assets", [])
                    if a.get("name", "").lower() == "baixador.exe"), "")
        if url:
            notas = (j.get("body") or "").strip().splitlines()
            ATUALIZACAO.update(versao=tag.lstrip("vV"), notas=notas[0][:160] if notas else "", url=url)
    except Exception:
        log("atualização: " + traceback.format_exc().strip().splitlines()[-1])


def aplicar_atualizacao():
    """Baixa o .exe novo, troca pelo atual e reabre."""
    if ATUALIZACAO["estado"] == "baixando" or not ATUALIZACAO["url"]:
        return
    ATUALIZACAO["estado"], ATUALIZACAO["pct"] = "baixando", 0
    novo = EXE_APP + ".novo"
    try:
        req = urllib.request.Request(ATUALIZACAO["url"], headers=NAVEGADOR)
        with urllib.request.urlopen(req, timeout=60) as r, open(novo, "wb") as f:
            total = int(r.headers.get("Content-Length") or 0)
            feito = 0
            while True:
                bloco = r.read(256 * 1024)
                if not bloco:
                    break
                f.write(bloco)
                feito += len(bloco)
                if total:
                    ATUALIZACAO["pct"] = round(feito * 100 / total)
        if os.path.getsize(novo) < 5_000_000:
            raise RuntimeError("arquivo baixado incompleto")
        os.makedirs(PASTA_APP, exist_ok=True)
        if os.path.exists(EXE_APP):
            velho = EXE_APP + ".antigo"
            try:
                os.remove(velho)
            except OSError:
                pass
            os.replace(EXE_APP, velho)
        os.replace(novo, EXE_APP)
        ATUALIZACAO["estado"] = "pronto"
        subprocess.Popen([EXE_APP, "--nova"], cwd=PASTA_APP, close_fds=True)
        threading.Timer(1.0, lambda: os._exit(0)).start()
    except Exception:
        ATUALIZACAO["estado"] = "erro"
        log("aplicar atualização: " + traceback.format_exc())
        try:
            os.remove(novo)
        except OSError:
            pass


def _wheel_pypi(pacote, filtro):
    with urllib.request.urlopen(urllib.request.Request(f"https://pypi.org/pypi/{pacote}/json", headers=NAVEGADOR),
                                timeout=20) as r:
        j = json.loads(r.read().decode("utf-8"))
    for arq in j.get("urls", []):
        if arq.get("packagetype") == "bdist_wheel" and filtro(arq["filename"]):
            return j["info"]["version"], arq["url"]
    return j["info"]["version"], ""


def atualizar_ytdlp_exe():
    """No .exe não há pip: baixa o yt-dlp novo direto do PyPI para a pasta libs (vale na próxima abertura)."""
    cfg = ler_config()
    if time.time() - float(cfg.get("yt_atualizado") or 0) < 2 * 86400:
        return
    try:
        nova, url = _wheel_pypi("yt-dlp", lambda n: n.endswith("py3-none-any.whl"))
        if url and _versao_tupla(nova) > _versao_tupla(versao_ytdlp()):
            dados, _, _ = baixar_url(url, timeout=120)
            tmp = LIBS + ".tmp"
            shutil.rmtree(tmp, ignore_errors=True)
            with zipfile.ZipFile(io.BytesIO(dados)) as z:
                for m in z.namelist():
                    if m.startswith("yt_dlp/"):
                        z.extract(m, tmp)
            if not os.path.exists(os.path.join(tmp, "yt_dlp", "__init__.py")):
                raise RuntimeError("pacote do yt-dlp incompleto")
            shutil.rmtree(LIBS, ignore_errors=True)
            os.replace(tmp, LIBS)
            log(f"yt-dlp {nova} baixado (vale na próxima abertura)")
        salvar_config(yt_atualizado=time.time())
    except Exception:
        log("yt-dlp: " + traceback.format_exc().strip().splitlines()[-1])


def tarefas_de_fundo():
    """Depois que a tela abre: gera/atualiza o aplicativo, procura versão nova e mantém o yt-dlp em dia."""
    if os.name != "nt" or DEMO:
        return
    time.sleep(4)
    try:
        if not CONGELADO:
            if not exe_em_dia():
                gerar_exe("(primeira vez ou programa novo)")
            atualizar_ytdlp_de_vez_em_quando()
            return
        for velho in (EXE_APP + ".antigo", EXE_APP + ".novo"):
            try:
                os.remove(velho)
            except OSError:
                pass
        atualizar_ytdlp_exe()
        while True:
            procurar_atualizacao()
            time.sleep(3 * 3600)
    except Exception:
        log("fundo: " + traceback.format_exc())


# ================================================================ componentes (yt-dlp, Pillow, janela, ffmpeg)
def garantir_libs():
    if CONGELADO:
        return
    faltam = []
    mods = [("yt_dlp", "yt-dlp"), ("PIL", "pillow")]
    if os.name == "nt":
        mods.append(("webview", "pywebview"))
    for mod, pacote in mods:
        try:
            __import__(mod)
        except Exception:
            faltam.append(pacote)
    if not faltam:
        return
    etapa("Instalando componentes (só na primeira vez, pode levar 1 ou 2 minutos)", 30)
    pip(faltam)


def pip(pacotes, atualizar=False):
    if CONGELADO:
        return
    py = python_do_sistema()
    base = [py, "-m", "pip", "install", "--quiet", "--disable-pip-version-check"]
    if atualizar:
        base.append("-U")
    for extra in ([], ["--user"]):
        try:
            r = subprocess.run(base + extra + pacotes, creationflags=NO_WINDOW, stdin=subprocess.DEVNULL,
                               stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=900)
            if r.returncode == 0:
                break
            erro = r.stderr.decode("utf-8", "replace")
            log("pip falhou " + " ".join(extra) + ":\n" + erro[-1500:])
            if "No module named pip" in erro:
                subprocess.run([py, "-m", "ensurepip", "--upgrade"], creationflags=NO_WINDOW,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
        except Exception:
            log("pip: " + traceback.format_exc())
    import importlib, site
    importlib.invalidate_caches()
    try:
        up = site.getusersitepackages()
        if up and os.path.isdir(up) and up not in sys.path:
            sys.path.append(up)
    except Exception:
        pass


def atualizar_ytdlp_de_vez_em_quando():
    """O YouTube muda sempre; a cada 3 dias atualiza o yt-dlp em segundo plano (vale na próxima abertura)."""
    cfg = ler_config()
    if time.time() - float(cfg.get("yt_atualizado") or 0) < 3 * 86400:
        return
    pip(["yt-dlp"], atualizar=True)
    salvar_config(yt_atualizado=time.time())


def ffmpeg_funciona(exe):
    try:
        return subprocess.run([exe, "-version"], capture_output=True, creationflags=NO_WINDOW,
                              timeout=15).returncode == 0
    except Exception:
        return False


def achar_ffmpeg():
    """Devolve a PASTA que contém um ffmpeg que funciona, ou None."""
    nome = "ffmpeg.exe" if os.name == "nt" else "ffmpeg"
    proprio = os.path.join(BASE, "ffmpeg_bin", nome)
    if os.path.exists(proprio) and ffmpeg_funciona(proprio):
        return os.path.dirname(proprio)
    exe = shutil.which("ffmpeg")
    if exe and ffmpeg_funciona(exe):
        return os.path.dirname(exe)
    base = os.path.join(os.environ.get("LOCALAPPDATA", ""), "Microsoft", "WinGet", "Packages")
    for exe in glob.glob(os.path.join(base, "*FFmpeg*", "**", "ffmpeg.exe"), recursive=True):
        if ffmpeg_funciona(exe):
            return os.path.dirname(exe)
    etapa("Baixando o conversor de áudio (só na primeira vez, uns 30 MB)", 70)
    if CONGELADO:
        try:
            _, url = _wheel_pypi("imageio-ffmpeg", lambda n: "win_amd64" in n or "win-amd64" in n)
            dados, _, _ = baixar_url(url, timeout=300)
            with zipfile.ZipFile(io.BytesIO(dados)) as z:
                nome_bin = next(n for n in z.namelist() if "/binaries/ffmpeg" in n and n.endswith(".exe"))
                os.makedirs(os.path.dirname(proprio), exist_ok=True)
                with z.open(nome_bin) as a, open(proprio + ".tmp", "wb") as b:
                    shutil.copyfileobj(a, b)
            os.replace(proprio + ".tmp", proprio)
            if ffmpeg_funciona(proprio):
                return os.path.dirname(proprio)
        except Exception:
            log("ffmpeg (download): " + traceback.format_exc())
        return None
    try:
        import imageio_ffmpeg  # noqa
    except Exception:
        pip(["imageio-ffmpeg"])
    try:
        import imageio_ffmpeg
        os.makedirs(os.path.dirname(proprio), exist_ok=True)
        shutil.copy2(imageio_ffmpeg.get_ffmpeg_exe(), proprio)
        if ffmpeg_funciona(proprio):
            return os.path.dirname(proprio)
    except Exception:
        log("ffmpeg: " + traceback.format_exc())
    return None


FFMPEG = None


# ================================================================ configuração
def ler_config():
    return ler_json(CONFIG, {})


def salvar_config(**mudancas):
    cfg = ler_config()
    cfg.update(mudancas)
    gravar_json(CONFIG, cfg)
    return cfg


# ================================================================ pendrives
def listar_pendrives():
    if os.name != "nt":
        return []
    achados = []
    mascara = ctypes.windll.kernel32.GetLogicalDrives()
    for i in range(26):
        if mascara & (1 << i):
            letra = f"{chr(65 + i)}:\\"
            if ctypes.windll.kernel32.GetDriveTypeW(letra) == 2:  # removível
                achados.append(letra)
    return achados


def info_unidade(letra):
    try:
        total, _, livre = shutil.disk_usage(letra)
    except Exception:
        return None
    if not total:
        return None
    nome = ""
    try:
        buf = ctypes.create_unicode_buffer(261)
        if ctypes.windll.kernel32.GetVolumeInformationW(letra, buf, 261, None, None, None, None, 0):
            nome = buf.value.strip()
    except Exception:
        pass
    return {"letra": letra, "nome": nome or "Pendrive", "total": total, "livre": livre}


DRIVES = {}


def vigia_pendrives():
    global DRIVES
    while True:
        try:
            atuais = {}
            for letra in listar_pendrives():
                if letra in DRIVES and os.path.exists(letra):
                    atuais[letra] = DRIVES[letra]
                else:
                    info = info_unidade(letra)
                    if info:
                        atuais[letra] = info
            DRIVES = atuais
        except Exception:
            pass
        time.sleep(1.0)


def tam(b):
    gb = b / 1024 ** 3
    if gb >= 100:
        return f"{gb:.0f} GB"
    if gb >= 1:
        return f"{gb:.1f} GB".replace(".", ",")
    return f"{b / 1024 ** 2:.0f} MB"


def descrever_destino(destino):
    d = destino or ""
    unidade = os.path.splitdrive(d)[0].upper()
    if unidade:
        for letra, info in DRIVES.items():
            if letra[:2].upper() == unidade:
                try:
                    info["livre"] = shutil.disk_usage(letra).free
                except Exception:
                    pass
                return {"tipo": "pendrive", "nome": f"{info['nome']} ({letra[:2]})",
                        "sub": f"{tam(info['livre'])} livres de {tam(info['total'])}", "path": d}
    if os.path.normcase(os.path.normpath(d)) == os.path.normcase(os.path.normpath(PASTA_MUSICAS)):
        return {"tipo": "musicas", "nome": "Pasta Músicas", "sub": d, "path": d}
    return {"tipo": "outra", "nome": os.path.basename(d.rstrip("\\/")) or d, "sub": d, "path": d}


def estado_destinos():
    cfg = ler_config()
    destino = cfg.get("destino") or PASTA_MUSICAS
    removido = None
    unidade = os.path.splitdrive(destino)[0].upper()
    if cfg.get("destino_pendrive") and unidade and not any(l[:2].upper() == unidade for l in DRIVES):
        removido = unidade
        destino = PASTA_MUSICAS
        salvar_config(destino=destino, destino_pendrive=False)
    pendrives = [{"letra": l, "nome": i["nome"], "rotulo": f"{i['nome']} ({l[:2]})",
                  "sub": f"{tam(i['livre'])} livres de {tam(i['total'])}"} for l, i in sorted(DRIVES.items())]
    return {"destino": descrever_destino(destino), "pendrives": pendrives, "musicas": PASTA_MUSICAS,
            "formato": cfg.get("formato", "mp3"), "removido": removido, "ffmpeg": bool(FFMPEG),
            "app": APP["estado"], "congelado": CONGELADO,
            "atualizacao": ATUALIZACAO if ATUALIZACAO["url"] else None}


# ================================================================ YouTube (busca, prévia, download)
class LogYT:
    def __init__(self):
        self.ultimo_erro = ""

    def debug(self, msg):
        pass

    def info(self, msg):
        pass

    def warning(self, msg):
        pass

    def error(self, msg):
        self.ultimo_erro = ANSI.sub("", str(msg))


def fmt_tempo(seg):
    seg = max(0, int(seg))
    if seg >= 3600:
        return f"{seg // 3600}:{seg % 3600 // 60:02d}:{seg % 60:02d}"
    return f"{seg // 60}:{seg % 60:02d}"


def fmt_views(n):
    if not n:
        return ""
    for lim, suf in ((1e9, " bi"), (1e6, " mi"), (1e3, " mil")):
        if n >= lim:
            v = n / lim
            return (f"{v:.1f}".rstrip("0").rstrip(".").replace(".", ",") if v < 10 else f"{v:.0f}") + suf
    return str(int(n))


def buscar(termo, quantos):
    eh_link = termo.lower().startswith(("http://", "https://", "www."))
    if termo.lower().startswith("www."):
        termo = "https://" + termo
    if DEMO:
        time.sleep(0.8)
        return demo_resultados(termo, quantos), quantos >= 40
    import yt_dlp
    opts = {"quiet": True, "no_warnings": True, "extract_flat": True, "noprogress": True,
            "noplaylist": True, "logger": LogYT()}
    with yt_dlp.YoutubeDL(opts) as ydl:
        if eh_link:
            info = ydl.extract_info(termo, download=False)
            entradas = list(info.get("entries") or [info])
            fim = True
        else:
            info = ydl.extract_info(f"ytsearch{quantos}:{termo}", download=False)
            entradas = list(info.get("entries") or [])
            fim = len(entradas) < quantos
    res, vistos = [], set()
    for e in entradas:
        if not e:
            continue
        vid = e.get("id") or ""
        url = e.get("webpage_url") or e.get("url") or ""
        if (not url or not url.startswith("http")) and vid:
            url = "https://www.youtube.com/watch?v=" + vid
        if not url or url in vistos:
            continue
        vistos.add(url)
        dur = int(e.get("duration") or 0)
        mini = f"https://i.ytimg.com/vi/{vid}/mqdefault.jpg" if len(vid) == 11 else (e.get("thumbnail") or "")
        if not mini and e.get("thumbnails"):
            mini = e["thumbnails"][-1].get("url", "")
        res.append({"titulo": e.get("title") or "(sem título)",
                    "canal": e.get("channel") or e.get("uploader") or "",
                    "tempo": fmt_tempo(dur) if dur else "", "dur": dur,
                    "views": fmt_views(e.get("view_count")), "url": url, "mini": mini})
    return res, fim


PREVIAS = {}       # url do vídeo -> (endereço direto, cabeçalhos)
STREAMS = {}       # id curto -> url do vídeo


def fonte_previa(url):
    if url in PREVIAS:
        return PREVIAS[url]
    import yt_dlp
    opts = {"quiet": True, "no_warnings": True, "noplaylist": True, "skip_download": True,
            "format": PREVIA_FORMATO, "logger": LogYT()}
    with yt_dlp.YoutubeDL(opts) as ydl:
        info = ydl.extract_info(url, download=False)
    f = info if info.get("url") else (info.get("requested_formats") or [{}])[0]
    PREVIAS[url] = (f["url"], dict(f.get("http_headers") or info.get("http_headers") or {}))
    return PREVIAS[url]


# ---------------------------------------------------------------- fila de downloads
TAREFAS = []
FILA = queue.Queue()
TRAVA = threading.Lock()


def nova_tarefa(dados):
    cfg = ler_config()
    fmt = dados.get("formato") or cfg.get("formato", "mp3")
    destino = cfg.get("destino") or PASTA_MUSICAS
    t = {"id": secrets.token_hex(5), "url": dados["url"], "titulo": dados.get("titulo") or "",
         "mini": dados.get("mini") or "", "canal": dados.get("canal") or "", "formato": fmt,
         "destino": destino, "destino_nome": descrever_destino(destino)["nome"], "estado": "fila",
         "pct": 0.0, "vel": "", "eta": "", "arquivo": "", "erro": "", "criado": time.time()}
    with TRAVA:
        TAREFAS.append(t)
    FILA.put(t)
    return t


def trabalhador_downloads():
    while True:
        t = FILA.get()
        if t.get("cancelada"):
            continue
        try:
            executar_download(t)
        except Exception as ex:
            t["estado"], t["erro"] = "erro", ANSI.sub("", str(ex))[:300]
            log("download: " + traceback.format_exc())


def executar_download(t):
    t["estado"] = "baixando"
    pasta = t["destino"]
    try:
        os.makedirs(pasta, exist_ok=True)
    except Exception:
        t["estado"], t["erro"] = "erro", "Não consegui usar essa pasta. Se for pendrive, veja se está conectado."
        return
    if t["formato"] == "mp3" and not FFMPEG and not DEMO:
        t["estado"], t["erro"] = "erro", "Para baixar música é preciso o ffmpeg. Feche e abra o Baixador de novo."
        return
    if DEMO:
        for i in range(41):
            time.sleep(0.12)
            t["pct"], t["vel"], t["eta"] = i * 2.5, "2,4 MB/s", f"0:{(40 - i) // 8:02d}"
        t["estado"] = "convertendo"
        time.sleep(1.2)
        t["estado"], t["pct"], t["arquivo"] = "pronto", 100, t["titulo"] + "." + t["formato"]
        return
    import yt_dlp
    lg = LogYT()

    def gancho(d):
        if d["status"] == "downloading":
            total = d.get("total_bytes") or d.get("total_bytes_estimate")
            if total:
                t["pct"] = min(99.0, d.get("downloaded_bytes", 0) * 100 / total)
            v = d.get("speed")
            t["vel"] = (f"{v / 1024 ** 2:.1f} MB/s".replace(".", ",") if v else "")
            e = d.get("eta")
            t["eta"] = fmt_tempo(e) if e is not None else ""
        elif d["status"] == "finished":
            t["estado"], t["pct"] = "convertendo", 99.0

    opts = {"outtmpl": os.path.join(pasta, "%(title)s.%(ext)s"), "noplaylist": True, "quiet": True,
            "no_warnings": True, "noprogress": True, "windowsfilenames": True,
            "progress_hooks": [gancho], "logger": lg}
    if FFMPEG:
        opts["ffmpeg_location"] = FFMPEG
    if t["formato"] == "mp3":
        opts["format"] = "bestaudio/best"
        opts["postprocessors"] = [{"key": "FFmpegExtractAudio", "preferredcodec": "mp3",
                                   "preferredquality": "192"}]
    elif FFMPEG:
        opts["format"] = "bv*[height<=1080]+ba/b[height<=1080]/b"
        opts["merge_output_format"] = "mp4"
    else:
        opts["format"] = "b[ext=mp4]/b"
    arquivos = []
    try:
        with yt_dlp.YoutubeDL(opts) as ydl:
            info = ydl.extract_info(t["url"], download=True)
            for r in info.get("requested_downloads", []) or []:
                if r.get("filepath"):
                    arquivos.append(r["filepath"])
    except Exception as ex:
        t["estado"] = "erro"
        t["erro"] = (lg.ultimo_erro or ANSI.sub("", str(ex)))[:300]
        return
    final = arquivos[-1] if arquivos else ""
    if t["formato"] == "mp3" and final and not final.lower().endswith(".mp3"):
        t["estado"], t["erro"] = "erro", "não foi possível converter para MP3"
        return
    t["arquivo"] = os.path.basename(final) if final else info.get("title", "")
    t["caminho"] = final
    t["estado"], t["pct"] = "pronto", 100.0


def tarefas_publicas():
    with TRAVA:
        return [dict(t) for t in TAREFAS[-60:]]


# ================================================================ fontes do dafont
def baixar_url(url, referer=None, timeout=20):
    cab = dict(NAVEGADOR)
    if referer:
        cab["Referer"] = referer
    req = urllib.request.Request(url, headers=cab)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read(), r.headers.get_content_charset(), r.headers.get_content_type()


def baixar_html(url):
    dados, charset, _ = baixar_url(url, referer=DAFONT)
    for cod in (charset, "utf-8", "latin-1"):
        if cod:
            try:
                return dados.decode(cod)
            except Exception:
                continue
    return dados.decode("utf-8", "replace")


def _sem_tags(t):
    return " ".join(html.unescape(re.sub(r"<[^>]+>", " ", t)).split())


LICENCAS = ("Domínio público / GPL / OFL", "100% Grátis", "Grátis para uso pessoal",
            "Shareware", "Demo", "Doar ao autor")


def ler_lista_dafont(pagina_html, base):
    blocos = re.split(r'(?=<div[^>]*class="[^"]*\blv1left\b)', pagina_html)
    if len(blocos) < 2:
        blocos = re.split(r'(?=<a[^>]+href="[^"]+\.font"[^>]*>\s*<strong>)', pagina_html)
    fontes, vistos = [], set()
    for b in blocos[1:]:
        m = re.search(r'dl\.dafont\.com/dl/\?f=([\w\-]+)', b)
        if not m:
            continue
        slug = m.group(1)
        if slug in vistos:
            continue
        vistos.add(slug)
        nome, pag = "", ""
        for m2 in re.finditer(r'<a[^>]+href="([^"]+\.font)"[^>]*>(.*?)</a>', b, re.S):
            texto = _sem_tags(m2.group(2))
            pag = pag or urllib.parse.urljoin(base, html.unescape(m2.group(1)))
            if texto:
                nome = texto
                break
        autor = ""
        m2 = re.search(r'<a[^>]+href="[^"]+\.d\d+"[^>]*>(.*?)</a>', b, re.S)
        if m2:
            autor = _sem_tags(m2.group(1))
        texto_bloco = _sem_tags(b)
        m2 = re.search(r'([\d\.,]+)\s+downloads', texto_bloco)
        downloads = m2.group(1) if m2 else ""
        licenca = ""
        m2 = re.search(r'faq\.php#copyright"[^>]*>(.*?)</a>', b, re.S)
        if m2:
            licenca = _sem_tags(m2.group(1))
        if not licenca:
            licenca = next((l for l in LICENCAS if l in texto_bloco), "")
        m2 = re.search(r'background-image:\s*url\(\s*[\'"]?([^\'")]+)', b)
        if m2:
            previa = urllib.parse.urljoin(base, html.unescape(m2.group(1)))
        else:
            previa = f"https://www.dafont.com/img/preview/{slug[0]}/{slug[1:2] or slug[0]}/{slug}0.png"
        fontes.append({"slug": slug, "nome": nome or slug.replace("_", " ").title(), "autor": autor,
                       "downloads": downloads, "licenca": licenca,
                       "pagina": pag or urllib.parse.urljoin(base, slug.replace("_", "-") + ".font"),
                       "previa": previa})
    paginas = [int(n) for n in re.findall(r'[?&;]page=(\d+)', pagina_html)]
    return fontes, max(paginas + [1])


def registro_fontes():
    reg = {"baixadas": {}, "instaladas": []}
    reg.update(ler_json(REGISTRO_FONTES, {}))
    return reg


# categorias do dafont: lidas do menu do próprio site (ficam guardadas 7 dias); se o site falhar, usa esta lista
CATEGORIAS_RESERVA = [
    (1, "Fantasia", [(101, "Desenho"), (102, "Quadrinhos"), (103, "Groovy"), (104, "Old School"), (105, "Enrolada"),
                     (106, "Faroeste"), (107, "Corroída"), (108, "Distorcida"), (109, "Destruída"), (110, "Terror"),
                     (111, "Fogo, gelo"), (112, "Decorativa"), (113, "Máquina de escrever"), (114, "Estêncil, exército"),
                     (115, "Retrô"), (116, "Iniciais"), (117, "Grade"), (118, "Diversas")]),
    (2, "Estrangeiras", [(201, "Chinesa, japonesa"), (202, "Árabe"), (203, "Mexicana"), (204, "Romana, grega"),
                         (205, "Russa"), (206, "Diversas")]),
    (3, "Techno", [(301, "Quadrada"), (302, "LCD"), (303, "Ficção científica"), (304, "Diversas")]),
    (4, "Gótica", [(401, "Medieval"), (402, "Moderna"), (403, "Celta"), (404, "Iniciais"), (405, "Diversas")]),
    (5, "Básica", [(501, "Sans Serif"), (502, "Serif"), (503, "Largura fixa"), (504, "Diversas")]),
    (6, "Escrita", [(601, "Caligrafia"), (602, "Escolar"), (603, "Manuscrita"), (604, "Pincel"), (605, "Trash"),
                    (606, "Grafite"), (607, "Old School"), (608, "Diversas")]),
    (7, "Dingbats", []),
    (10, "Feriados", [(1001, "Dia dos Namorados"), (1002, "Páscoa"), (1003, "Halloween"), (1004, "Natal"),
                      (1005, "Diversas")]),
]
CAT_PATH = os.path.join(BASE, "fontes_categorias.json")
RE_CAT = re.compile(r"^(theme\.php\?cat=\d+|mtheme\.php\?id=\d+|bitmap\.php)$")


def ler_categorias_site():
    pg = baixar_html(DAFONT)
    grupos, ordem = {}, []
    for m in re.finditer(r'href=["\']?[^"\'>]*?mtheme\.php\?id=(\d+)[^>]*>(.*?)</a>', pg, re.S):
        gid, nome = int(m.group(1)), _sem_tags(m.group(2))
        if nome and gid not in grupos:
            grupos[gid] = {"nome": nome, "url": f"mtheme.php?id={gid}", "subs": []}
            ordem.append(gid)
    vistos = set()
    for m in re.finditer(r'href=["\']?[^"\'>]*?(?<![a-z])theme\.php\?cat=(\d+)[^>]*>(.*?)</a>', pg, re.S):
        cat, nome = int(m.group(1)), _sem_tags(m.group(2))
        if not nome or cat in vistos:
            continue
        vistos.add(cat)
        gid = cat // 100
        if gid not in grupos:
            grupos[gid] = {"nome": "Outras", "url": "", "subs": []}
            ordem.append(gid)
        grupos[gid]["subs"].append({"nome": nome, "url": f"theme.php?cat={cat}"})
    lista = [grupos[g] for g in ordem if grupos[g]["subs"] or grupos[g]["url"]]
    m = re.search(r'href=["\']?[^"\'>]*?bitmap\.php[^>]*>(.*?)</a>', pg, re.S)
    if m:
        lista.append({"nome": _sem_tags(m.group(1)) or "Bitmap", "url": "bitmap.php", "subs": []})
    if sum(len(g["subs"]) for g in lista) < 20:
        raise RuntimeError(f"menu do site não reconhecido ({len(pg)} bytes, {len(vistos)} categorias)")
    return lista


def categorias_fontes():
    guardado = ler_json(CAT_PATH, {})
    if guardado.get("lista") and time.time() - float(guardado.get("quando") or 0) < 7 * 86400:
        return guardado["lista"]
    if not DEMO:
        try:
            lista = ler_categorias_site()
            gravar_json(CAT_PATH, {"quando": time.time(), "lista": lista})
            return lista
        except Exception:
            log("categorias: " + traceback.format_exc().strip().splitlines()[-1])
    if guardado.get("lista"):
        return guardado["lista"]
    reserva = [{"nome": n, "url": f"mtheme.php?id={g}", "subs": [{"nome": sn, "url": f"theme.php?cat={c}"}
                                                             for c, sn in subs]}
            for g, n, subs in CATEGORIAS_RESERVA] + [{"nome": "Bitmap", "url": "bitmap.php", "subs": []}]
    if not DEMO:   # tenta o site de novo só amanhã
        gravar_json(CAT_PATH, {"quando": time.time() - 6 * 86400, "lista": reserva})
    return reserva


def nome_categoria(caminho):
    for g in categorias_fontes():
        if g["url"] == caminho:
            return g["nome"] + " › Todas"
        for sub in g["subs"]:
            if sub["url"] == caminho:
                return g["nome"] + " › " + sub["nome"]
    return "Fontes"


def listar_fontes(modo, termo, p, cat=""):
    if modo != "busca":
        cat = cat if RE_CAT.match(cat or "") else FONTES_CAT_PADRAO
        salvar_config(fonte_cat=cat)
    if DEMO:
        time.sleep(0.6)
        fontes = [{"slug": f"demo_{i}", "nome": n, "autor": "Autor " + str(i), "downloads": f"{(i + 3) * 1371:,}".replace(",", "."),
                   "licenca": LICENCAS[i % 3], "pagina": DAFONT, "previa": ""} for i, n in enumerate(
            ["Old London", "Blackletter Pro", "Canterbury", "Fette Fraktur", "Gothic Ultra", "Medieval Sharp",
             "Kingthings", "Grusskarten Gotisch"])]
        total = 5
    else:
        if modo == "busca":
            url = FONTES_BUSCA.format(urllib.parse.quote_plus(termo), p)
        else:
            url = DAFONT + cat + ("&" if "?" in cat else "?") + f"page={p}"
        fontes, total = ler_lista_dafont(baixar_html(url), url)
    reg = registro_fontes()
    for f in fontes:
        pasta = reg["baixadas"].get(f["slug"])
        f["baixada"] = pasta if pasta and os.path.isdir(pasta) else ""
        f["instalada"] = f["slug"] in reg["instaladas"]
        f["livre"] = "público" in f["licenca"] or "100%" in f["licenca"]
    return {"fontes": fontes, "total": max(total, p), "pagina": p, "cat": cat,
            "titulo": f"Resultados para “{termo}”" if modo == "busca" else nome_categoria(cat)}


def arquivos_da_fonte(slug):
    pasta = os.path.join(PASTA_CACHE_FONTES, slug)
    prontos = [os.path.join(pasta, n) for n in sorted(os.listdir(pasta))] if os.path.isdir(pasta) else []
    if prontos:
        return prontos
    dados, _, _ = baixar_url(FONTES_DOWNLOAD.format(slug), referer=DAFONT, timeout=60)
    try:
        z = zipfile.ZipFile(io.BytesIO(dados))
    except zipfile.BadZipFile:
        raise RuntimeError("o site não mandou um arquivo de fonte válido")
    temp = pasta + ".tmp"
    shutil.rmtree(temp, ignore_errors=True)
    os.makedirs(temp)
    achados = []
    for info in z.infolist():
        nome = os.path.basename(info.filename)
        if info.is_dir() or "__MACOSX" in info.filename or nome.startswith("._"):
            continue
        if not nome.lower().endswith((".ttf", ".otf")):
            continue
        with z.open(info) as a, open(os.path.join(temp, nome), "wb") as b:
            shutil.copyfileobj(a, b)
        achados.append(nome)
    if not achados:
        shutil.rmtree(temp, ignore_errors=True)
        raise RuntimeError("o arquivo baixado não tem fontes .ttf ou .otf")
    shutil.rmtree(pasta, ignore_errors=True)
    os.replace(temp, pasta)
    return [os.path.join(pasta, n) for n in sorted(achados)]


def instalar_fonte_usuario(arq):
    import winreg
    from PIL import ImageFont
    pasta = os.path.join(os.environ["LOCALAPPDATA"], "Microsoft", "Windows", "Fonts")
    os.makedirs(pasta, exist_ok=True)
    destino = os.path.join(pasta, os.path.basename(arq))
    if not os.path.exists(destino):
        shutil.copy2(arq, destino)
    try:
        familia, estilo = ImageFont.truetype(destino, 12).getname()
    except Exception:
        familia, estilo = os.path.splitext(os.path.basename(arq))[0], ""
    nome = familia if (estilo or "").lower() in ("", "regular", "normal") else f"{familia} {estilo}"
    nome += " (OpenType)" if destino.lower().endswith(".otf") else " (TrueType)"
    with winreg.CreateKeyEx(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows NT\CurrentVersion\Fonts",
                            0, winreg.KEY_SET_VALUE) as k:
        winreg.SetValueEx(k, nome, 0, winreg.REG_SZ, destino)
    ctypes.windll.gdi32.AddFontResourceW(destino)


def acao_fonte(slug, nome, acao):
    reg = registro_fontes()
    if DEMO:
        time.sleep(1.2)
        resultado = PASTA_FONTES_BAIXADAS if acao == "baixar" else 2
    else:
        arquivos = arquivos_da_fonte(slug)
        if acao == "baixar":
            pasta = os.path.join(PASTA_FONTES_BAIXADAS, re.sub(r'[\\/:*?"<>|]+', "", nome).strip(" .") or "fonte")
            os.makedirs(pasta, exist_ok=True)
            for a in arquivos:
                shutil.copy2(a, pasta)
            resultado = pasta
        else:
            if os.name != "nt":
                raise RuntimeError("instalar fontes só funciona no Windows")
            for a in arquivos:
                instalar_fonte_usuario(a)
            try:
                ctypes.windll.user32.SendMessageTimeoutW(0xFFFF, 0x001D, 0, 0, 0x0002, 1000, None)
            except Exception:
                pass
            resultado = len(arquivos)
    if acao == "baixar":
        reg["baixadas"][slug] = resultado
    elif slug not in reg["instaladas"]:
        reg["instaladas"].append(slug)
    gravar_json(REGISTRO_FONTES, reg)
    return resultado


CACHE_IMG = {}


def imagem_remota(url):
    if url in CACHE_IMG:
        return CACHE_IMG[url]
    dados, _, tipo = baixar_url(url, referer=DAFONT, timeout=15)
    if len(CACHE_IMG) > 400:
        CACHE_IMG.clear()
    CACHE_IMG[url] = (dados, tipo or "image/png")
    return CACHE_IMG[url]


# ================================================================ imagens (busca no Bing Imagens; reserva: Openverse)
IMG_POR_PAG = 35
EXT_IMG = {"image/jpeg": ".jpg", "image/jpg": ".jpg", "image/png": ".png", "image/gif": ".gif",
           "image/webp": ".webp", "image/bmp": ".bmp", "image/avif": ".avif", "image/svg+xml": ".svg"}


def _dominio(url):
    try:
        d = urllib.parse.urlsplit(url).hostname or ""
        return d[4:] if d.startswith("www.") else d
    except Exception:
        return ""


def imagens_bing(termo, p):
    url = ("https://www.bing.com/images/async?" + urllib.parse.urlencode(
        {"q": termo, "first": (p - 1) * IMG_POR_PAG + 1, "count": IMG_POR_PAG, "mmasync": 1, "setlang": "pt-br"}))
    req = urllib.request.Request(url, headers=dict(NAVEGADOR, Cookie="SRCHHPGUSR=ADLT=MODERATE"))
    with urllib.request.urlopen(req, timeout=20) as r:
        pg = r.read().decode("utf-8", "replace")
    res, vistos = [], set()
    for m in re.finditer(r'\sm="(\{[^"]+\})"', pg):
        try:
            j = json.loads(html.unescape(m.group(1)))
        except Exception:
            continue
        full = j.get("murl") or ""
        if not full.startswith("http") or full in vistos:
            continue
        vistos.add(full)
        res.append({"url": full, "mini": j.get("turl") or full, "titulo": _sem_tags(j.get("t") or ""),
                    "pagina": j.get("purl") or "", "site": _dominio(j.get("purl") or full)})
    return res


def imagens_openverse(termo, p):
    url = "https://api.openverse.org/v1/images/?" + urllib.parse.urlencode(
        {"q": termo, "page": p, "page_size": 30, "mature": "false"})
    dados, _, _ = baixar_url(url, timeout=20)
    j = json.loads(dados.decode("utf-8"))
    res = []
    for r in j.get("results", []):
        if not r.get("url"):
            continue
        res.append({"url": r["url"], "mini": r.get("thumbnail") or r["url"], "titulo": r.get("title") or "",
                    "pagina": r.get("foreign_landing_url") or "",
                    "site": _dominio(r.get("foreign_landing_url") or r["url"]),
                    "larg": r.get("width"), "alt": r.get("height")})
    return res, int(j.get("page_count") or p)


def buscar_imagens(termo, p):
    if DEMO:
        time.sleep(0.7)
        res = []
        for i in range(30):
            h = (len(termo) * 47 + i * 37 + p * 11) % 360
            a, b = 200 + (i * 53) % 260, 160 + (i * 71) % 240
            svg = (f"<svg xmlns='http://www.w3.org/2000/svg' width='{a}' height='{b}'><defs><linearGradient id='g' "
                   f"x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='hsl({h},70%,55%)'/><stop offset='1' "
                   f"stop-color='hsl({(h + 60) % 360},70%,30%)'/></linearGradient></defs>"
                   f"<rect width='100%' height='100%' fill='url(#g)'/></svg>")
            u = "data:image/svg+xml," + urllib.parse.quote(svg)
            res.append({"url": u, "mini": u, "titulo": f"{termo} {i + 1}", "pagina": "", "site": "exemplo.com.br",
                        "larg": a * 4, "alt": b * 4})
        return {"res": res, "fonte": "demo", "fim": p >= 6}
    try:
        res = imagens_bing(termo, p)
        if res or p > 1:
            return {"res": res, "fonte": "bing", "fim": len(res) < 10}
    except Exception:
        log("imagens bing: " + traceback.format_exc().strip().splitlines()[-1])
    res, total = imagens_openverse(termo, p)
    return {"res": res, "fonte": "openverse", "fim": p >= total or not res}


def nome_livre(pasta, base, ext):
    base = re.sub(r'[\\/:*?"<>|\r\n\t]+', " ", base or "").strip(" .")[:80].strip() or "imagem"
    cand = os.path.join(pasta, base + ext)
    n = 2
    while os.path.exists(cand):
        cand = os.path.join(pasta, f"{base} ({n}){ext}")
        n += 1
    return cand


def baixar_imagem(dados):
    pasta = ler_config().get("destino") or PASTA_MUSICAS
    os.makedirs(pasta, exist_ok=True)
    titulo = (dados.get("titulo") or dados.get("q") or "imagem").strip()
    menor = False
    if DEMO:
        time.sleep(0.6)
        caminho = nome_livre(pasta, titulo, ".jpg")
        with open(caminho, "wb") as f:
            f.write(b"demo")
    else:
        conteudo, tipo = None, ""
        for i, u in enumerate([dados.get("url"), dados.get("mini")]):
            if not u or not u.startswith("http"):
                continue
            try:
                ref = dados.get("pagina") or ("https://" + _dominio(u) + "/")
                c, _, t = baixar_url(u, referer=ref, timeout=30)
                if len(c) < 200:
                    raise RuntimeError("arquivo vazio")
                conteudo, tipo, menor = c, (t or "").lower(), i == 1
                break
            except Exception:
                log("imagem: " + traceback.format_exc().strip().splitlines()[-1])
        if conteudo is None:
            raise RuntimeError("o site da imagem não deixou baixar")
        assin = conteudo[:16]
        if not tipo.startswith("image/"):
            tipo = ("image/png" if assin.startswith(b"\x89PNG") else "image/gif" if assin[:3] == b"GIF"
                    else "image/webp" if assin[8:12] == b"WEBP" else "image/jpeg" if assin[:2] == b"\xff\xd8" else "")
            if not tipo:
                raise RuntimeError("o endereço não é de uma imagem")
        ext = EXT_IMG.get(tipo.split(";")[0].strip(), ".jpg")
        if ext in (".webp", ".avif", ".bmp"):          # converte para um formato que abre em qualquer lugar
            try:
                from PIL import Image
                im = Image.open(io.BytesIO(conteudo))
                transp = im.mode in ("RGBA", "LA") or (im.mode == "P" and "transparency" in im.info)
                saida = io.BytesIO()
                if transp:
                    im.convert("RGBA").save(saida, "PNG")
                    ext = ".png"
                else:
                    im.convert("RGB").save(saida, "JPEG", quality=95)
                    ext = ".jpg"
                conteudo = saida.getvalue()
            except Exception:
                log("converter imagem: " + traceback.format_exc().strip().splitlines()[-1])
        caminho = nome_livre(pasta, titulo, ext)
        with open(caminho, "wb") as f:
            f.write(conteudo)
    t = {"id": secrets.token_hex(5), "url": dados.get("url", "")[:500], "titulo": titulo,
         "mini": dados.get("mini", "") if not str(dados.get("mini", "")).startswith("data:") else "",
         "canal": dados.get("site", ""), "formato": "img", "destino": pasta,
         "destino_nome": descrever_destino(pasta)["nome"], "estado": "pronto", "pct": 100.0, "vel": "", "eta": "",
         "arquivo": os.path.basename(caminho), "caminho": caminho, "erro": "", "criado": time.time(),
         "menor": menor}
    with TRAVA:
        TAREFAS.append(t)
    return t


# ================================================================ diálogos do Windows (pasta e área de transferência)
TK_TRAVA = threading.Lock()


def escolher_pasta(inicial):
    p = escolher_pasta_janela(inicial)
    if p is not None:
        return p
    with TK_TRAVA:
        import tkinter as tk
        from tkinter import filedialog
        r = tk.Tk()
        r.withdraw()
        r.attributes("-topmost", True)
        try:
            p = filedialog.askdirectory(parent=r, initialdir=inicial or None, title="Escolha a pasta onde guardar")
        finally:
            r.destroy()
        return os.path.normpath(p) if p else ""


def ler_area_transferencia():
    with TK_TRAVA:
        import tkinter as tk
        r = tk.Tk()
        r.withdraw()
        try:
            return r.clipboard_get().strip()
        except Exception:
            return ""
        finally:
            r.destroy()


def abrir_no_explorer(alvo, selecionar=False):
    try:
        if os.name == "nt":
            if selecionar and os.path.isfile(alvo):
                subprocess.Popen(["explorer", "/select,", alvo])
            else:
                os.startfile(alvo)
        elif sys.platform == "darwin":
            subprocess.Popen(["open", alvo])
        else:
            subprocess.Popen(["xdg-open", alvo])
    except Exception:
        log("abrir: " + traceback.format_exc())


# ================================================================ dados de demonstração
def demo_resultados(termo, quantos):
    nomes = ["Ao Vivo", "Clipe Oficial", "Acústico", "Lyric Video", "Remix", "Versão Estendida",
             "Audio Oficial", "Live Session", "Cover", "Karaokê"]
    res = []
    for i in range(min(quantos, 40)):
        dur = 140 + (i * 37) % 260
        res.append({"titulo": f"{termo.title()} – {nomes[i % len(nomes)]}", "canal": f"Canal {i % 7 + 1}",
                    "tempo": fmt_tempo(dur), "dur": dur, "views": fmt_views(12345 * (i + 1) ** 3),
                    "url": f"https://www.youtube.com/watch?v=demo{i:07d}", "mini": ""})
    return res


# ================================================================ servidor local
TOKEN = secrets.token_urlsafe(18)
ULTIMO_PING = [time.time()]
FECHANDO = [0.0]


def ha_download_ativo():
    with TRAVA:
        return any(t["estado"] in ("fila", "baixando", "convertendo") for t in TAREFAS)


def guarda_fechamento():
    """Fecha o programa quando a janela some (e nada estiver baixando)."""
    while True:
        time.sleep(2)
        agora = time.time()
        if ha_download_ativo() or APP["estado"] == "gerando":
            continue
        if FECHANDO[0] and agora - FECHANDO[0] > 6 and ULTIMO_PING[0] < FECHANDO[0]:
            os._exit(0)
        if agora - ULTIMO_PING[0] > 150:
            os._exit(0)


class Servidor(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = os.name != "nt"

    def server_bind(self):
        if os.name == "nt" and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            try:
                self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            except OSError:
                pass
        super().server_bind()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "Baixador"

    def log_message(self, *a):
        pass

    def _enviar(self, codigo, corpo, tipo="application/json; charset=utf-8", extra=None):
        if isinstance(corpo, str):
            corpo = corpo.encode("utf-8")
        self.send_response(codigo)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(corpo)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        try:
            self.wfile.write(corpo)
        except Exception:
            pass

    def _json(self, obj, codigo=200):
        self._enviar(codigo, json.dumps(obj, ensure_ascii=False))

    def _host_ok(self):
        h = (self.headers.get("Host") or "").split(":")[0]
        return h in ("127.0.0.1", "localhost")

    def _token_ok(self, qs):
        return self.headers.get("X-T") == TOKEN or (qs.get("t") or [""])[0] == TOKEN

    def _corpo(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    def do_GET(self):
        if not self._host_ok():
            return self._enviar(403, "{}")
        u = urllib.parse.urlsplit(self.path)
        p, qs = u.path, urllib.parse.parse_qs(u.query)
        if p == "/":
            return self._enviar(200, PAGINA.replace("__TOKEN__", TOKEN).replace("__VERSAO__", VERSAO),
                                "text/html; charset=utf-8")
        if p == "/logo.svg":
            return self._enviar(200, LOGO_SVG, "image/svg+xml", {"Cache-Control": "max-age=86400"})
        if p.startswith("/fontes/") and p.endswith(".ttf"):
            arq = os.path.join(PASTA_FONTES_APP, os.path.basename(p))
            if os.path.exists(arq):
                with open(arq, "rb") as f:
                    return self._enviar(200, f.read(), "font/ttf", {"Cache-Control": "max-age=86400"})
            return self._enviar(404, "")
        if p == "/api/ping":
            if (qs.get("inst") or [""])[0]:
                return self._json({"app": "baixador", "build": BUILD})
        if not p.startswith("/api/") or not self._token_ok(qs):
            return self._enviar(403, "{}")
        ULTIMO_PING[0] = time.time()
        try:
            if p == "/api/ping":
                return self._json({"ok": True})
            if p == "/api/estado":
                return self._json(dict(ESTADO, janela=JANELA["modo"], congelado=CONGELADO))
            if p == "/api/destinos":
                return self._json(estado_destinos())
            if p == "/api/buscar":
                termo = (qs.get("q") or [""])[0].strip()
                n = max(10, min(200, int((qs.get("n") or ["10"])[0])))
                try:
                    res, fim = buscar(termo, n)
                    return self._json({"res": res, "fim": fim})
                except Exception as ex:
                    log("busca: " + traceback.format_exc())
                    return self._json({"erro": ANSI.sub("", str(ex))[:300]}, 500)
            if p == "/api/previa":
                url = (qs.get("u") or [""])[0]
                if DEMO:
                    return self._json({"erro": "demo"}, 404)
                try:
                    fonte_previa(url)
                    sid = hashlib.sha1(url.encode()).hexdigest()[:16]
                    STREAMS[sid] = url
                    return self._json({"src": f"/api/stream/{sid}?t={TOKEN}"})
                except Exception as ex:
                    return self._json({"erro": str(ex)[:200]}, 500)
            if p.startswith("/api/stream/"):
                return self._stream(p.rsplit("/", 1)[-1])
            if p == "/api/tarefas":
                return self._json({"tarefas": tarefas_publicas()})
            if p == "/api/fontes":
                modo = (qs.get("modo") or ["cat"])[0]
                termo = (qs.get("q") or [""])[0]
                pg = max(1, int((qs.get("p") or ["1"])[0]))
                cat = (qs.get("cat") or [""])[0] or ler_config().get("fonte_cat") or FONTES_CAT_PADRAO
                try:
                    return self._json(listar_fontes(modo, termo, pg, cat))
                except Exception as ex:
                    log("fontes: " + traceback.format_exc())
                    return self._json({"erro": str(ex)[:200]}, 500)
            if p == "/api/imagens":
                termo = (qs.get("q") or [""])[0].strip()
                pg = max(1, int((qs.get("p") or ["1"])[0]))
                try:
                    return self._json(buscar_imagens(termo, pg))
                except Exception as ex:
                    log("imagens: " + traceback.format_exc())
                    return self._json({"erro": str(ex)[:200]}, 500)
            if p == "/api/categorias":
                return self._json({"grupos": categorias_fontes(),
                                   "atual": ler_config().get("fonte_cat") or FONTES_CAT_PADRAO})
            if p == "/api/img":
                url = (qs.get("u") or [""])[0]
                if not url.startswith("https://www.dafont.com/") and not url.startswith("https://img.dafont.com/"):
                    return self._enviar(403, "")
                try:
                    dados, tipo = imagem_remota(url)
                    return self._enviar(200, dados, tipo, {"Cache-Control": "max-age=86400"})
                except Exception:
                    return self._enviar(404, "")
            if p == "/api/colar":
                return self._json({"texto": ler_area_transferencia()})
        except Exception:
            log("GET " + p + ": " + traceback.format_exc())
            return self._json({"erro": "falha interna"}, 500)
        self._enviar(404, "{}")

    def do_POST(self):
        if not self._host_ok():
            return self._enviar(403, "{}")
        u = urllib.parse.urlsplit(self.path)
        p, qs = u.path, urllib.parse.parse_qs(u.query)
        if not self._token_ok(qs):
            return self._enviar(403, "{}")
        dados = self._corpo()
        ULTIMO_PING[0] = time.time()
        try:
            if p == "/api/fechar":
                FECHANDO[0] = time.time()
                return self._json({"ok": True})
            if p == "/api/config":
                mud = {}
                if dados.get("formato") in ("mp3", "mp4"):
                    mud["formato"] = dados["formato"]
                if "destino" in dados:
                    d = dados["destino"] or PASTA_MUSICAS
                    if os.path.normcase(d) != os.path.normcase(PASTA_MUSICAS) and not os.path.isdir(d):
                        return self._json({"erro": "Não consegui acessar esse local. Escolha outro."}, 400)
                    mud["destino"] = d
                    mud["destino_pendrive"] = any(l[:2].upper() == d[:2].upper() for l in DRIVES)
                salvar_config(**mud)
                return self._json(estado_destinos())
            if p == "/api/escolher_pasta":
                return self._json({"path": escolher_pasta(dados.get("inicial") or "")})
            if p == "/api/baixar":
                if not dados.get("url"):
                    return self._json({"erro": "nada escolhido"}, 400)
                return self._json({"tarefa": nova_tarefa(dados)})
            if p == "/api/cancelar":
                with TRAVA:
                    for t in TAREFAS:
                        if t["id"] == dados.get("id") and t["estado"] == "fila":
                            t["cancelada"], t["estado"] = True, "cancelada"
                return self._json({"ok": True})
            if p == "/api/limpar":
                with TRAVA:
                    TAREFAS[:] = [t for t in TAREFAS if t["estado"] in ("fila", "baixando", "convertendo")]
                return self._json({"ok": True})
            if p == "/api/abrir":
                alvo = dados.get("path") or (ler_config().get("destino") or PASTA_MUSICAS)
                abrir_no_explorer(alvo, bool(dados.get("selecionar")))
                return self._json({"ok": True})
            if p == "/api/site":
                url = dados.get("url") or ""
                if url.startswith("https://"):
                    webbrowser.open(url)
                return self._json({"ok": True})
            if p == "/api/imagem":
                try:
                    return self._json({"tarefa": baixar_imagem(dados)})
                except Exception as ex:
                    return self._json({"erro": str(ex)[:200]}, 500)
            if p == "/api/fonte":
                try:
                    r = acao_fonte(dados["slug"], dados.get("nome") or dados["slug"], dados.get("acao"))
                    return self._json({"ok": True, "resultado": r})
                except Exception as ex:
                    log("fonte: " + traceback.format_exc())
                    return self._json({"erro": str(ex)[:200]}, 500)
            if p == "/api/mostrar":
                threading.Thread(target=trazer_para_frente, daemon=True).start()
                return self._json({"ok": True})
            if p == "/api/atualizar":
                threading.Thread(target=aplicar_atualizacao, daemon=True).start()
                return self._json({"ok": True})
            if p == "/api/abrir_app":
                if not os.path.exists(EXE_APP):
                    return self._json({"erro": "o aplicativo ainda não está pronto"}, 400)
                subprocess.Popen([EXE_APP, "--nova"], cwd=PASTA_APP, close_fds=True)
                threading.Timer(0.8, lambda: os._exit(0)).start()
                return self._json({"ok": True})
            if p == "/api/quit":
                if APP["estado"] == "gerando":     # não interrompe a geração do aplicativo
                    threading.Thread(target=trazer_para_frente, daemon=True).start()
                    return self._json({"ocupado": True})
                threading.Timer(0.3, lambda: os._exit(0)).start()
                return self._json({"ok": True})
        except Exception:
            log("POST " + p + ": " + traceback.format_exc())
            return self._json({"erro": "falha interna"}, 500)
        self._enviar(404, "{}")

    def _stream(self, sid):
        url = STREAMS.get(sid)
        if not url or url not in PREVIAS:
            return self._enviar(404, "")
        endereco, cab = PREVIAS[url]
        cab = dict(cab)
        rng = self.headers.get("Range")
        if rng:
            cab["Range"] = rng
        try:
            resp = urllib.request.urlopen(urllib.request.Request(endereco, headers=cab), timeout=20)
        except urllib.error.HTTPError as e:
            return self._enviar(e.code if e.code in (403, 404, 416) else 502, "")
        except Exception:
            return self._enviar(502, "")
        with resp:
            self.send_response(resp.status)
            for k in ("Content-Type", "Content-Length", "Content-Range", "Accept-Ranges"):
                if resp.headers.get(k):
                    self.send_header(k, resp.headers[k])
            self.send_header("Cache-Control", "no-store")
            if not resp.headers.get("Content-Length"):
                self.send_header("Connection", "close")
                self.close_connection = True
            self.end_headers()
            try:
                while True:
                    bloco = resp.read(64 * 1024)
                    if not bloco:
                        break
                    self.wfile.write(bloco)
            except Exception:
                self.close_connection = True


def abrir_janela_edge(url):
    """Reserva: Edge/Chrome em modo aplicativo (quando a janela própria não estiver disponível)."""
    cands = [r"%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe",
             r"%ProgramFiles%\Microsoft\Edge\Application\msedge.exe",
             r"%ProgramFiles%\Google\Chrome\Application\chrome.exe",
             r"%ProgramFiles(x86)%\Google\Chrome\Application\chrome.exe",
             r"%LocalAppData%\Google\Chrome\Application\chrome.exe"]
    for c in cands:
        exe = os.path.expandvars(c)
        if os.path.exists(exe):
            try:
                subprocess.Popen([exe, f"--app={url}", "--start-maximized",
                                  f"--user-data-dir={os.path.join(BASE, 'janela')}", "--no-first-run",
                                  "--no-default-browser-check", "--disable-features=Translate",
                                  "--autoplay-policy=no-user-gesture-required"])
                return
            except Exception:
                log("Falha ao abrir " + exe)
    webbrowser.open(url)


# ---------------------------------------------------------------- janela própria (pywebview / WebView2)
JANELA = {"win": None, "modo": "edge", "url": ""}


def _hwnds_do_processo():
    achados = []
    if os.name != "nt":
        return achados
    u = ctypes.windll.user32
    pid = os.getpid()
    PROC = ctypes.WINFUNCTYPE(ctypes.c_bool, ctypes.c_void_p, ctypes.c_void_p)

    def cb(h, _):
        p = ctypes.c_ulong()
        u.GetWindowThreadProcessId(ctypes.c_void_p(h), ctypes.byref(p))
        if p.value == pid and u.IsWindowVisible(ctypes.c_void_p(h)) and not u.GetWindow(ctypes.c_void_p(h), 4):
            achados.append(h)
        return True
    u.EnumWindows(PROC(cb), 0)
    return achados


def enfeitar_janela():
    """Ícone nítido (no tamanho certo para a tela) e barra de título escura, como um aplicativo do Windows."""
    if os.name != "nt":
        return
    u, dwm = ctypes.windll.user32, ctypes.windll.dwmapi
    ico = garantir_icone()
    u.LoadImageW.restype = ctypes.c_void_p
    for h in _hwnds_do_processo():
        hw = ctypes.c_void_p(h)
        try:
            dpi = u.GetDpiForWindow(hw) or 96
        except Exception:
            dpi = 96
        for tipo, base in ((1, 32), (0, 16)):     # ICON_BIG, ICON_SMALL
            lado = round(base * dpi / 96)
            hi = u.LoadImageW(None, ico, 1, lado, lado, 0x0010) if ico else None   # LR_LOADFROMFILE
            if hi:
                u.SendMessageW(hw, 0x0080, tipo, ctypes.c_void_p(hi))           # WM_SETICON
        sim = ctypes.c_int(1)
        for attr in (20, 19):                                                  # DWMWA_USE_IMMERSIVE_DARK_MODE
            if dwm.DwmSetWindowAttribute(hw, attr, ctypes.byref(sim), 4) == 0:
                break
        cor = ctypes.c_uint(0x00160B0C)                                       # #0C0B16 (BGR)
        dwm.DwmSetWindowAttribute(hw, 35, ctypes.byref(cor), 4)                # cor da barra de título (Win 11)
        txt = ctypes.c_uint(0x00FAEFF1)
        dwm.DwmSetWindowAttribute(hw, 36, ctypes.byref(txt), 4)


def trazer_para_frente():
    w = JANELA["win"]
    if w is not None:
        try:
            w.restore()
        except Exception:
            pass
        try:
            w.show()
        except Exception:
            pass
        if os.name == "nt":
            for h in _hwnds_do_processo():
                ctypes.windll.user32.ShowWindow(ctypes.c_void_p(h), 9)
                ctypes.windll.user32.SetForegroundWindow(ctypes.c_void_p(h))
    else:
        abrir_janela_edge(JANELA["url"])


def rodar_janela_propria(url):
    """Abre a janela do Baixador (bloqueia até ela fechar). Devolve False se não der para usar o pywebview."""
    try:
        import webview
    except Exception:
        log("pywebview indisponível: " + traceback.format_exc().splitlines()[-1])
        return False
    try:
        w = webview.create_window("Baixador", url, width=1320, height=860, min_size=(960, 640),
                                  background_color="#08080F", text_select=True)
    except TypeError:
        w = webview.create_window("Baixador", url, width=1320, height=860, min_size=(960, 640))
    JANELA["win"], JANELA["modo"] = w, "propria"

    def ao_mostrar():
        try:
            w.maximize()
        except Exception:
            pass
        for espera in (0, 0.6, 2.0):
            time.sleep(espera)
            try:
                enfeitar_janela()
            except Exception:
                log("enfeitar: " + traceback.format_exc())

    def ao_fechar():
        if ha_download_ativo():
            try:
                return bool(w.create_confirmation_dialog(
                    "Baixador", "Ainda tem download em andamento. Se fechar agora, ele para. Fechar mesmo assim?"))
            except Exception:
                return True
        return True
    try:
        w.events.shown += lambda: threading.Thread(target=ao_mostrar, daemon=True).start()
        w.events.closing += ao_fechar
    except Exception:
        pass
    opcoes = {"private_mode": False, "storage_path": os.path.join(BASE, "janela_webview")}
    if os.name == "nt":
        opcoes["gui"] = "edgechromium"
    try:
        webview.start(**opcoes)
    except TypeError:
        webview.start()
    except Exception:
        log("janela própria falhou: " + traceback.format_exc())
        JANELA["win"], JANELA["modo"] = None, "edge"
        return False
    return True


def escolher_pasta_janela(inicial):
    w = JANELA["win"]
    if w is None:
        return None
    try:
        import webview
        tipo = getattr(webview, "FOLDER_DIALOG", None)
        if tipo is None:
            tipo = webview.FileDialog.FOLDER
        r = w.create_file_dialog(tipo, directory=inicial or "")
        if r:
            return os.path.normpath(r[0] if isinstance(r, (list, tuple)) else r)
        return ""
    except Exception:
        log("diálogo de pasta: " + traceback.format_exc())
        return None


def instancia_aberta():
    try:
        inst = ler_json(INST_PATH, {})
        porta = int(inst.get("porta") or 0)
        if not porta:
            return None
        op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        with op.open(f"http://127.0.0.1:{porta}/api/ping?inst=1", timeout=1.5) as r:
            j = json.loads(r.read().decode("utf-8"))
        if j.get("app") != "baixador":
            return None
        tok = inst.get("token", "")
        if j.get("build") == BUILD:
            try:
                op.open(urllib.request.Request(f"http://127.0.0.1:{porta}/api/mostrar?t={tok}", data=b"{}"),
                        timeout=3).read()
            except Exception:
                pass
            return porta
        log(f"Versão diferente aberta ({j.get('build')}); fechando para abrir a {BUILD}.")
        try:
            with op.open(urllib.request.Request(f"http://127.0.0.1:{porta}/api/quit?t={tok}", data=b"{}"),
                         timeout=2) as r:
                if json.loads(r.read().decode("utf-8") or "{}").get("ocupado"):
                    return porta          # a outra está gerando o aplicativo: deixa ela terminar
        except Exception:
            pass
        time.sleep(1.5)
        return None
    except Exception:
        return None


def preparar():
    global FFMPEG
    try:
        etapa("Verificando componentes", 14)
        garantir_libs()
        etapa("Carregando o buscador de vídeos", 52)
        try:
            import yt_dlp  # noqa
        except Exception:
            ESTADO["erro"] = ("Não consegui instalar os componentes. Verifique a internet e abra de novo. "
                              "(detalhes em baixador_log.txt)")
            log("yt_dlp: " + traceback.format_exc())
            return
        etapa("Procurando o conversor de áudio", 64)
        FFMPEG = achar_ffmpeg()
        ESTADO["ffmpeg"] = bool(FFMPEG)
        etapa("Preparando o aplicativo", 86)
        instalar_copia()
        garantir_icone()
        if CONGELADO:
            instalar_exe_baixado()
        else:
            criar_atalhos()
        etapa("Pronto", 100)
        ESTADO["pronto"] = True
        threading.Thread(target=tarefas_de_fundo, daemon=True).start()
    except Exception:
        log("preparar: " + traceback.format_exc())
        ESTADO["erro"] = "Algo deu errado ao abrir. Detalhes em baixador_log.txt."


def preparar_demo():
    global FFMPEG
    FFMPEG = "demo"
    for m, pc in (("Verificando componentes", 20), ("Carregando o buscador de vídeos", 55),
                  ("Procurando o conversor de áudio", 78), ("Pronto", 100)):
        etapa(m, pc)
        time.sleep(0.5)
    ESTADO["ffmpeg"] = True
    ESTADO["pronto"] = True


def fonte_mais_nova_que_o_exe():
    if not CONGELADO or not os.path.exists(FONTE_PROG):
        return None
    try:
        with open(FONTE_PROG, "rb") as f:
            b = hashlib.sha1(f.read()).hexdigest()[:12]
        if b == info_app().get("build"):
            return None
        py = python_do_sistema()
        pyw = os.path.join(os.path.dirname(py or ""), "pythonw.exe")
        return pyw if py and os.path.exists(pyw) else None
    except Exception:
        return None


def principal():
    sem_janela = "--no-window" in sys.argv
    pyw = fonte_mais_nova_que_o_exe()
    if pyw and "--nova" not in sys.argv:   # há versão nova do programa: ela abre e gera o .exe atualizado
        try:
            subprocess.Popen([pyw, "-x", FONTE_PROG], cwd=BASE, close_fds=True)
            return
        except Exception:
            log("abrir fonte nova: " + traceback.format_exc())
    # o .bat virou instalador: se o aplicativo (.exe) já está em dia, abre ele e sai
    if not CONGELADO and not DEMO and not sem_janela and "--nova" not in sys.argv and exe_em_dia():
        try:
            subprocess.Popen([EXE_APP], cwd=PASTA_APP, close_fds=True)
            return
        except Exception:
            log("abrir exe: " + traceback.format_exc())
    if "--nova" not in sys.argv:
        if instancia_aberta():
            return
    porta_fixa = 0
    for a in sys.argv:
        if a.startswith("--porta="):
            porta_fixa = int(a.split("=", 1)[1])
    srv = Servidor(("127.0.0.1", porta_fixa), Handler)
    porta = srv.server_address[1]
    url = f"http://127.0.0.1:{porta}/"
    JANELA["url"] = url
    gravar_json(INST_PATH, {"porta": porta, "token": TOKEN, "build": BUILD})
    for letra in listar_pendrives():
        info = info_unidade(letra)
        if info:
            DRIVES[letra] = info
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    threading.Thread(target=vigia_pendrives, daemon=True).start()
    for _ in range(2):
        threading.Thread(target=trabalhador_downloads, daemon=True).start()
    threading.Thread(target=preparar_demo if DEMO else preparar, daemon=True).start()
    if sem_janela:
        print(url, flush=True)
        while True:
            time.sleep(3600)
    if rodar_janela_propria(url):
        # janela fechada: se ainda estiver gerando o aplicativo, termina isso antes de sair (sem janela)
        while APP["estado"] == "gerando":
            time.sleep(2)
        os._exit(0)
    abrir_janela_edge(url)
    threading.Thread(target=guarda_fechamento, daemon=True).start()
    while True:
        time.sleep(3600)

# ================================================================ interface (HTML + CSS + JS)
LOGO_SVG = r"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#7C5CFF"/><stop offset=".55" stop-color="#D946EF"/><stop offset="1" stop-color="#FF6A3D"/></linearGradient><linearGradient id="h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".32"/><stop offset=".5" stop-color="#fff" stop-opacity="0"/></linearGradient></defs><rect width="64" height="64" rx="18" fill="url(#g)"/><rect width="64" height="64" rx="18" fill="url(#h)"/><g stroke="#fff" stroke-linecap="round" stroke-linejoin="round" fill="none"><path d="M13 28v8M20 21v19M44 21v19M51 28v8" stroke-width="4.6" opacity=".92"/><path d="M32 13v26" stroke-width="5.2"/><path d="M26.5 34l5.5 5.5 5.5-5.5" stroke-width="5.2"/><path d="M19 50h26" stroke-width="4.6" opacity=".92"/></g></svg>"""

PAGINA = r"""<!doctype html>
<html lang="pt-BR">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Baixador</title>
<link rel="icon" href="/logo.svg" type="image/svg+xml">
<style>
@font-face{font-family:"InterL";src:url(/fontes/Inter-Regular.ttf) format("truetype");font-weight:400 500}
@font-face{font-family:"InterL";src:url(/fontes/Inter-Bold.ttf) format("truetype");font-weight:600 900}
:root{
  --bg:#08080f;--bg2:#0c0b16;--card:#13121f;--card2:#1a1829;--card3:#221f35;--line:#262339;--line2:#36324f;
  --text:#f1effa;--muted:#9a95b5;--mute2:#6c6788;
  --a1:#7c5cff;--a2:#d946ef;--a3:#ff6a3d;--ok:#34d399;--bad:#fb7185;--info:#60a5fa;--warn:#fbbf24;
  --grad:linear-gradient(135deg,var(--a1),var(--a2) 55%,var(--a3));
  --sh:0 1px 2px rgba(0,0,0,.4),0 10px 30px -12px rgba(0,0,0,.7);
  --sh2:0 2px 6px rgba(0,0,0,.45),0 24px 48px -18px rgba(0,0,0,.9);
  --ease:cubic-bezier(.2,.8,.2,1);--r:18px;
}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{font-family:InterL,Inter,"Segoe UI Variable Text","Segoe UI",system-ui,sans-serif;background:var(--bg);color:var(--text);
  display:grid;grid-template-columns:262px 1fr;overflow:hidden;font-size:14.5px;line-height:1.5;-webkit-font-smoothing:antialiased}
button,input{font:inherit;color:inherit}
[hidden]{display:none!important}
#ovRoot{position:fixed;z-index:50}
button{cursor:pointer;border:0;background:none}
svg.i{width:20px;height:20px;stroke:currentColor;fill:none;stroke-width:2;stroke-linecap:round;stroke-linejoin:round;flex:none}
*{scrollbar-width:thin;scrollbar-color:var(--line2) transparent}
::selection{background:rgba(217,70,239,.35)}

/* fundo vivo */
.orbs{position:fixed;inset:0;z-index:0;pointer-events:none;overflow:hidden}
.orbs i{position:absolute;border-radius:50%;filter:blur(100px);opacity:.22;animation:floaty 26s ease-in-out infinite}
.orbs i:nth-child(1){width:460px;height:460px;background:var(--a1);top:-160px;right:8%}
.orbs i:nth-child(2){width:400px;height:400px;background:var(--a2);bottom:-170px;left:30%;animation-delay:-9s;animation-duration:32s;opacity:.16}
.orbs i:nth-child(3){width:280px;height:280px;background:var(--a3);top:40%;right:-100px;animation-delay:-15s;opacity:.12}
.noise{position:fixed;inset:0;z-index:0;pointer-events:none;opacity:.035;background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='160' height='160'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='.9' numOctaves='3'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E")}
@keyframes floaty{0%,100%{transform:translate(0,0) scale(1)}33%{transform:translate(44px,-34px) scale(1.08)}66%{transform:translate(-34px,44px) scale(.94)}}
@keyframes rise{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:none}}
@keyframes fade{from{opacity:0}}
@keyframes gshift{to{background-position:200% 0}}
@keyframes pop{0%{transform:scale(.6)}60%{transform:scale(1.15)}100%{transform:scale(1)}}
@keyframes shake{20%,60%{transform:translateX(-6px)}40%,80%{transform:translateX(6px)}}
@keyframes shimmer{to{background-position:-200% 0}}
@keyframes spin{to{transform:rotate(360deg)}}
@keyframes pulse{0%{box-shadow:0 0 0 0 rgba(52,211,153,.6)}100%{box-shadow:0 0 0 10px rgba(52,211,153,0)}}
@keyframes eq{0%,100%{transform:scaleY(.3)}50%{transform:scaleY(1)}}

/* barra lateral */
aside{position:relative;z-index:2;background:linear-gradient(180deg,rgba(19,18,31,.85),rgba(8,8,15,.85));border-right:1px solid var(--line);
  padding:22px 16px 18px;display:flex;flex-direction:column;gap:6px;backdrop-filter:blur(18px)}
.brand{display:flex;align-items:center;gap:12px;padding:2px 8px 24px}
.brand .lg{width:42px;height:42px;border-radius:13px;box-shadow:0 8px 22px -6px rgba(217,70,239,.6);transition:transform .4s var(--ease)}
.brand:hover .lg{transform:rotate(-8deg) scale(1.06)}
.brand b{font-size:19px;letter-spacing:-.3px;font-weight:800}
.brand small{display:block;color:var(--muted);font-size:11.5px;margin-top:-3px}
nav button{position:relative;width:100%;display:flex;align-items:center;gap:12px;padding:11px 12px;border-radius:12px;color:var(--muted);
  text-align:left;font-weight:600;transition:background .2s,color .2s;overflow:hidden}
nav button svg{transition:transform .3s var(--ease)}
nav button:hover{background:var(--card);color:var(--text)}
nav button:hover svg{transform:scale(1.15) rotate(-6deg)}
nav button.on{background:linear-gradient(90deg,rgba(124,92,255,.18),rgba(217,70,239,.12));color:var(--text);box-shadow:inset 0 0 0 1px var(--line)}
nav button.on svg{stroke:#c4b5fd}
nav button.on::before{content:"";position:absolute;left:0;top:22%;bottom:22%;width:3px;border-radius:0 3px 3px 0;background:var(--grad);animation:fade .3s}
.badge{margin-left:auto;min-width:22px;height:22px;padding:0 7px;border-radius:99px;background:var(--grad);color:#fff;font-size:11.5px;font-weight:800;display:grid;place-items:center}
.badge.zero{display:none}
.badge.bump{animation:pop .45s var(--ease)}
.sp{flex:1}
.sidecard{border:1px solid var(--line);background:rgba(19,18,31,.7);border-radius:16px;padding:14px;margin-top:8px}
.sidecard .lb{font-size:11px;letter-spacing:.9px;text-transform:uppercase;color:var(--mute2);font-weight:700;margin-bottom:10px}
.dest{display:flex;gap:11px;align-items:center}
.dest .ic{width:40px;height:40px;border-radius:12px;background:var(--card3);display:grid;place-items:center;color:#c4b5fd;flex:none;transition:background .3s}
.dest .ic.usb{background:rgba(52,211,153,.14);color:var(--ok)}
.dest b{display:block;font-size:13.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dest small{display:block;color:var(--muted);font-size:11.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dest>div{min-width:0}
.btn-ghost{width:100%;margin-top:12px;padding:9px 12px;border-radius:11px;background:var(--card2);border:1px solid var(--line);font-weight:600;font-size:13px;transition:.2s}
.btn-ghost:hover{background:var(--card3);border-color:var(--line2)}
.pill{display:flex;align-items:center;gap:9px;font-size:12.5px;color:var(--muted);padding:10px 12px;border-radius:12px;border:1px dashed var(--line);margin-top:8px;transition:.3s}
.pill i{width:8px;height:8px;border-radius:50%;background:var(--mute2);flex:none}
.pill.on{color:#a7f3d0;border-color:rgba(52,211,153,.35);background:rgba(52,211,153,.06)}
.pill.on i{background:var(--ok);animation:pulse 1.6s infinite}
.ver{font-size:11px;color:var(--mute2);text-align:center;margin-top:10px}

/* área principal */
main{position:relative;z-index:1;overflow:auto;scroll-behavior:smooth}
.wrap{max-width:1240px;margin:0 auto;padding:34px 40px 150px}
section{display:none}
section.on{display:block;animation:rise .45s var(--ease)}
.eyebrow{font-size:11.5px;letter-spacing:1.4px;text-transform:uppercase;color:var(--muted);font-weight:700;display:flex;align-items:center;gap:10px}
.eyebrow::before{content:"";width:22px;height:2px;border-radius:2px;background:var(--grad)}
h1{font-size:34px;letter-spacing:-1px;font-weight:800;margin:8px 0 4px;line-height:1.15}
.grad{background:linear-gradient(90deg,#a78bfa,#f0abfc,#fdba74,#a78bfa);background-size:200% auto;-webkit-background-clip:text;background-clip:text;color:transparent;animation:gshift 6s linear infinite}
.sub{color:var(--muted)}

/* alternador nome/link */
.seg{position:relative;display:inline-flex;padding:5px;border-radius:14px;background:var(--card);border:1px solid var(--line);margin:22px 0 14px}
.seg button{position:relative;z-index:1;padding:9px 18px;border-radius:10px;font-weight:600;color:var(--muted);display:flex;align-items:center;gap:8px;transition:color .25s}
.seg button svg{width:17px;height:17px}
.seg button.on{color:#fff}
.seg .ind{position:absolute;z-index:0;top:5px;bottom:5px;left:5px;border-radius:10px;background:var(--grad);box-shadow:0 8px 20px -8px rgba(217,70,239,.8);transition:transform .4s var(--ease),width .4s var(--ease)}

/* caixa de busca */
.search{display:flex;gap:10px;align-items:center;padding:8px;border-radius:20px;background:var(--card);border:1px solid var(--line);box-shadow:var(--sh);transition:border-color .25s,box-shadow .25s}
.search:focus-within{border-color:rgba(167,139,250,.6);box-shadow:0 0 0 4px rgba(124,92,255,.15),var(--sh)}
.search>svg{margin-left:12px;color:var(--muted)}
.search input{flex:1;min-width:0;background:transparent;border:0;outline:0;font-size:17px;padding:12px 4px}
.search input::placeholder{color:var(--mute2)}
.btn{display:inline-flex;align-items:center;justify-content:center;gap:8px;padding:12px 20px;border-radius:14px;font-weight:700;transition:transform .15s,box-shadow .25s,background .2s,opacity .2s;white-space:nowrap}
.btn:active{transform:scale(.96)}
.btn.pri{background:var(--grad);background-size:140% 140%;color:#fff;box-shadow:0 10px 24px -10px rgba(217,70,239,.9)}
.btn.pri:hover{box-shadow:0 14px 30px -10px rgba(217,70,239,1);transform:translateY(-1px)}
.btn.sec{background:var(--card2);border:1px solid var(--line)}
.btn.sec:hover{background:var(--card3);border-color:var(--line2)}
.btn.lg{padding:14px 26px;font-size:15.5px}
.btn[disabled]{opacity:.55;pointer-events:none}
.btn .spin{width:16px;height:16px;border-radius:50%;border:2px solid rgba(255,255,255,.35);border-top-color:#fff;animation:spin .7s linear infinite}

/* faixa de orientação */
.guia{display:flex;align-items:center;gap:12px;margin-top:16px;padding:13px 16px;border-radius:14px;font-weight:600;font-size:14.5px;
  border:1px solid;transition:background .35s,border-color .35s,color .35s}
.guia .gi{width:30px;height:30px;border-radius:9px;display:grid;place-items:center;flex:none;transition:background .35s}
.guia .gi svg{width:17px;height:17px}
.guia.aviso{background:rgba(124,92,255,.09);border-color:rgba(124,92,255,.28);color:#d4ccff}.guia.aviso .gi{background:rgba(124,92,255,.22)}
.guia.info{background:rgba(96,165,250,.08);border-color:rgba(96,165,250,.28);color:#bfdbfe}.guia.info .gi{background:rgba(96,165,250,.2)}
.guia.ok{background:rgba(52,211,153,.08);border-color:rgba(52,211,153,.3);color:#a7f3d0}.guia.ok .gi{background:rgba(52,211,153,.2)}
.guia.erro{background:rgba(251,113,133,.08);border-color:rgba(251,113,133,.32);color:#fecdd3}.guia.erro .gi{background:rgba(251,113,133,.2)}
.guia.troca span{animation:rise .35s var(--ease)}
.guia.erro.troca{animation:shake .4s}

/* resultados */
.rhead{display:flex;align-items:baseline;justify-content:space-between;margin:30px 2px 14px}
.rhead h2{font-size:18px;letter-spacing:-.3px}
.rhead small{color:var(--muted)}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(268px,1fr));gap:18px}
.vc{position:relative;border-radius:var(--r);background:var(--card);border:1px solid var(--line);padding:10px;cursor:pointer;
  transition:transform .35s var(--ease),box-shadow .35s var(--ease),border-color .3s,background .3s;animation:rise .5s var(--ease) both}
.vc:hover{transform:translateY(-5px);box-shadow:var(--sh2);border-color:var(--line2);background:var(--card2)}
.vc.sel{border-color:transparent;background:linear-gradient(var(--card2),var(--card2)) padding-box,var(--grad) border-box;border:2px solid transparent;padding:9px;
  box-shadow:0 18px 40px -16px rgba(217,70,239,.55)}
.thumb{position:relative;aspect-ratio:16/9;border-radius:12px;overflow:hidden;background:linear-gradient(135deg,hsl(var(--h,260) 50% 22%),hsl(calc(var(--h,260) + 50) 55% 14%))}
.thumb img,.thumb video{position:absolute;inset:0;width:100%;height:100%;object-fit:cover}
.thumb img{opacity:0;transition:opacity .5s,transform .6s var(--ease)}
.thumb img.in{opacity:1}
.vc:hover .thumb img{transform:scale(1.05)}
.thumb video{opacity:0;transition:opacity .35s}
.thumb video.in{opacity:1}
.thumb .ph{position:absolute;inset:0;display:grid;place-items:center;color:rgba(255,255,255,.25)}
.thumb .ph svg{width:46px;height:46px}
.dur{position:absolute;right:8px;bottom:8px;z-index:2;background:rgba(0,0,0,.78);color:#fff;font-size:12px;font-weight:700;padding:2px 7px;border-radius:6px;font-variant-numeric:tabular-nums;backdrop-filter:blur(4px)}
.pv{position:absolute;left:0;right:0;bottom:0;height:3px;background:rgba(255,255,255,.25);z-index:2;opacity:0;transition:opacity .3s}
.pv i{display:block;height:100%;width:0;background:#ff0033}
.thumb.tocando .pv{opacity:1}
.thumb .load{position:absolute;left:0;right:0;bottom:0;height:3px;z-index:3;opacity:0;background:linear-gradient(90deg,transparent,#fff,transparent);background-size:50% 100%;background-repeat:no-repeat;animation:varre 1s linear infinite}
@keyframes varre{from{background-position:-50% 0}to{background-position:150% 0}}
.thumb.carregando .load{opacity:.8}
.mudo{position:absolute;right:8px;top:8px;z-index:2;width:28px;height:28px;border-radius:50%;background:rgba(0,0,0,.6);display:grid;place-items:center;opacity:0;transition:opacity .3s}
.mudo svg{width:15px;height:15px;stroke:#fff}
.thumb.tocando .mudo{opacity:1}
.check{position:absolute;left:8px;top:8px;z-index:3;width:30px;height:30px;border-radius:50%;background:var(--grad);display:grid;place-items:center;transform:scale(0);transition:transform .35s var(--ease);box-shadow:0 6px 16px rgba(0,0,0,.45)}
.check svg{width:17px;height:17px;stroke:#fff;stroke-width:3}
.vc.sel .check{transform:scale(1)}
.vc .meta{padding:11px 4px 3px;display:flex;gap:10px;align-items:flex-start}
.vc .meta>div{min-width:0;flex:1}
.vc .tt{font-weight:700;font-size:14.5px;line-height:1.35;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.vc .ch{color:var(--muted);font-size:12.5px;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.quick{flex:none;width:36px;height:36px;border-radius:11px;background:var(--card3);display:grid;place-items:center;color:#e9d5ff;opacity:0;transform:translateY(4px);transition:.25s var(--ease)}
.quick svg{width:18px;height:18px}
.vc:hover .quick{opacity:1;transform:none}
.quick:hover{background:var(--grad);color:#fff}
.skel{border-radius:var(--r);background:var(--card);border:1px solid var(--line);padding:10px}
.skel .b{border-radius:10px;background:linear-gradient(90deg,var(--card2) 25%,var(--card3) 50%,var(--card2) 75%);background-size:200% 100%;animation:shimmer 1.3s linear infinite}
.vazio{text-align:center;padding:70px 20px;color:var(--muted)}
.vazio .eqv{display:flex;gap:6px;justify-content:center;align-items:flex-end;height:54px;margin-bottom:18px}
.vazio .eqv i{width:8px;height:100%;border-radius:4px;background:var(--grad);transform-origin:bottom;animation:eq 1.4s ease-in-out infinite;opacity:.8}
.vazio b{display:block;color:var(--text);font-size:17px;margin-bottom:4px}

/* páginas */
.pag{display:flex;justify-content:center;gap:6px;margin-top:28px;flex-wrap:wrap}
.pag button{min-width:42px;height:42px;padding:0 12px;border-radius:12px;background:var(--card);border:1px solid var(--line);font-weight:700;color:var(--muted);transition:.2s}
.pag button:hover{color:var(--text);border-color:var(--line2);transform:translateY(-1px)}
.pag button.on{background:var(--grad);color:#fff;border-color:transparent;box-shadow:0 8px 18px -8px rgba(217,70,239,.9)}
.pag button[disabled]{opacity:.35;pointer-events:none}
.pag span{align-self:center;color:var(--mute2);padding:0 4px}

/* doca de download */
.dock{position:fixed;left:calc(262px + 50%);transform:translateX(calc(-50% - 131px));bottom:22px;z-index:20;width:min(980px,calc(100vw - 262px - 60px));
  display:flex;align-items:center;gap:16px;padding:12px 12px 12px 12px;border-radius:22px;
  background:rgba(22,20,36,.82);border:1px solid var(--line2);box-shadow:0 30px 60px -20px rgba(0,0,0,.9),0 0 0 1px rgba(255,255,255,.02) inset;
  backdrop-filter:blur(22px) saturate(1.4);transition:transform .45s var(--ease),opacity .35s}
.dock.esc{transform:translate(calc(-50% - 131px),140%);opacity:0;pointer-events:none}
.dock .dt{width:112px;aspect-ratio:16/9;border-radius:11px;overflow:hidden;flex:none;position:relative;background:var(--card3)}
.dock .dt img{width:100%;height:100%;object-fit:cover}
.dock .dt .ph{position:absolute;inset:0;display:grid;place-items:center;color:var(--mute2)}
.dock .di{flex:1;min-width:0}
.dock .di small{font-size:11px;letter-spacing:1px;text-transform:uppercase;color:var(--mute2);font-weight:700}
.dock .di b{display:block;font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dock .di span{display:block;color:var(--muted);font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.dock.vaziad .di b{color:var(--muted);font-weight:600}
.dock.troca .di,.dock.troca .dt{animation:rise .4s var(--ease)}
.fmt{display:flex;padding:4px;border-radius:13px;background:var(--bg2);border:1px solid var(--line);position:relative;flex:none}
.fmt button{position:relative;z-index:1;padding:9px 14px;border-radius:9px;font-weight:700;color:var(--muted);display:flex;gap:7px;align-items:center;font-size:13.5px;transition:color .25s}
.fmt button svg{width:16px;height:16px}
.fmt button.on{color:#fff}
.fmt .ind{position:absolute;top:4px;bottom:4px;left:4px;border-radius:9px;background:var(--card3);box-shadow:inset 0 0 0 1px var(--line2);transition:transform .35s var(--ease),width .35s var(--ease)}
.dock .go{position:relative;overflow:hidden}
.dock .go::after{content:"";position:absolute;inset:0;background:linear-gradient(100deg,transparent 30%,rgba(255,255,255,.35) 50%,transparent 70%);transform:translateX(-100%)}
.dock .go.brilha::after{animation:brilho 1.1s ease}
@keyframes brilho{to{transform:translateX(100%)}}
.dock .mini{position:absolute;left:24px;right:24px;bottom:-1px;height:3px;border-radius:3px;overflow:hidden;opacity:0;transition:opacity .3s}
.dock .mini i{display:block;height:100%;width:0;background:var(--grad);transition:width .5s var(--ease)}
.dock.bx .mini{opacity:1}

/* fontes */
.frow{display:flex;gap:10px;flex-wrap:wrap;margin-top:22px}
.frow .search{flex:1;min-width:320px}
.cats{display:flex;gap:8px;flex-wrap:wrap;margin-top:22px}
.chip{padding:9px 17px;border-radius:99px;background:var(--card);border:1px solid var(--line);font-weight:700;font-size:13.5px;color:var(--muted);
  transition:transform .2s var(--ease),background .25s,color .25s,box-shadow .25s,border-color .25s;animation:rise .4s var(--ease) both}
.chip:hover{color:var(--text);border-color:var(--line2);transform:translateY(-2px)}
.chip.on{background:var(--grad);color:#fff;border-color:transparent;box-shadow:0 10px 22px -10px rgba(217,70,239,.9)}
.subs{display:flex;gap:6px;flex-wrap:wrap;margin-top:12px;padding:12px;border-radius:16px;background:rgba(19,18,31,.6);border:1px solid var(--line)}
.subs:empty{display:none}
.sub2{padding:7px 13px;border-radius:10px;font-size:13px;font-weight:600;color:var(--muted);border:1px solid transparent;transition:.2s;animation:rise .35s var(--ease) both}
.sub2:hover{color:var(--text);background:var(--card2)}
.sub2.on{background:var(--card3);color:var(--text);border-color:var(--line2);box-shadow:inset 0 -2px 0 #d946ef}
.appst{display:none;align-items:center;gap:9px;font-size:12px;color:#c4b5fd;padding:10px 12px;border-radius:12px;background:rgba(124,92,255,.08);border:1px solid rgba(124,92,255,.25);margin-top:8px}
.appst.on{display:flex;animation:rise .4s var(--ease)}
.appst .spin{width:14px;height:14px;border-radius:50%;border:2px solid rgba(196,181,253,.3);border-top-color:#c4b5fd;animation:spin .8s linear infinite;flex:none}
.nota{color:var(--mute2);font-size:12.5px;margin-top:12px}
.fc{display:grid;grid-template-columns:1fr auto;gap:6px 18px;align-items:center;padding:18px 20px;border-radius:var(--r);background:var(--card);border:1px solid var(--line);margin-bottom:12px;
  transition:transform .3s var(--ease),border-color .3s,box-shadow .3s;animation:rise .5s var(--ease) both}
.fc:hover{border-color:var(--line2);box-shadow:var(--sh2);transform:translateY(-2px)}
.fc h3{font-size:16.5px;letter-spacing:-.2px}
.fc .fm{color:var(--muted);font-size:12.5px}
.lic{display:inline-block;margin-top:6px;font-size:11px;font-weight:700;padding:3px 10px;border-radius:99px;background:rgba(124,92,255,.14);color:#c4b5fd}
.lic.livre{background:rgba(52,211,153,.12);color:#6ee7b7}
.fbtns{display:flex;gap:8px;grid-row:1/span 2;grid-column:2;align-self:start}
.fbtns .btn{padding:10px 15px;font-size:13.5px}
.fbtns .btn.feito{background:rgba(52,211,153,.12);color:#6ee7b7;box-shadow:none;pointer-events:none}
.fprev{grid-column:1/-1;margin-top:10px;min-height:64px;display:flex;align-items:center;border-radius:12px;background:var(--bg2);padding:10px 16px;overflow:hidden}
.fprev img{max-width:100%;max-height:96px;filter:invert(1);mix-blend-mode:screen;opacity:0;transition:opacity .5s}
.fprev img.in{opacity:.95}
.fprev .alt{font:400 34px/1.1 "Old English Text MT",UnifrakturMaguntia,Georgia,serif;color:#e9e4ff;opacity:.9}
.fprev.load{background:linear-gradient(90deg,var(--bg2) 25%,var(--card2) 50%,var(--bg2) 75%);background-size:200% 100%;animation:shimmer 1.3s linear infinite}

/* downloads */
.tk{display:grid;grid-template-columns:132px 1fr auto;gap:18px;align-items:center;padding:14px;border-radius:var(--r);background:var(--card);border:1px solid var(--line);margin-bottom:12px;animation:rise .45s var(--ease) both}
.tk .dt{aspect-ratio:16/9;border-radius:11px;overflow:hidden;position:relative;background:var(--card3)}
.tk .dt img{width:100%;height:100%;object-fit:cover}
.tk .dt .tag{position:absolute;left:6px;top:6px;font-size:10.5px;font-weight:800;padding:2px 7px;border-radius:6px;background:rgba(0,0,0,.7);letter-spacing:.5px}
.tk b{display:block;font-size:15px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tk .tm{color:var(--muted);font-size:12.5px;margin-top:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.tk>div{min-width:0}
.bar{height:7px;border-radius:99px;background:var(--card3);overflow:hidden;margin-top:10px;position:relative}
.bar i{display:block;height:100%;width:0;border-radius:99px;background:var(--grad);transition:width .6s var(--ease);position:relative}
.bar i::after{content:"";position:absolute;inset:0;background:linear-gradient(100deg,transparent,rgba(255,255,255,.5),transparent);transform:translateX(-100%);animation:brilho 1.4s ease-in-out infinite}
.tk.pronto .bar i{background:var(--ok)}.tk.pronto .bar i::after,.tk.erro .bar i::after{display:none}
.tk.erro .bar i{background:var(--bad)}
.st{display:inline-flex;align-items:center;gap:6px;font-size:12px;font-weight:700;padding:3px 10px;border-radius:99px;margin-top:8px}
.st.fila{background:var(--card3);color:var(--muted)}
.st.baixando,.st.convertendo{background:rgba(124,92,255,.16);color:#c4b5fd}
.st.pronto{background:rgba(52,211,153,.14);color:#6ee7b7}
.st.erro,.st.cancelada{background:rgba(251,113,133,.13);color:#fda4af}
.st .eqs{display:inline-flex;gap:2px;align-items:flex-end;height:10px}
.st .eqs i{width:2px;height:100%;background:currentColor;border-radius:1px;animation:eq .9s ease-in-out infinite;transform-origin:bottom}
.st .eqs i:nth-child(2){animation-delay:-.3s}.st .eqs i:nth-child(3){animation-delay:-.6s}
.tk .err{color:#fda4af;font-size:12px;margin-top:6px}


/* imagens */
.mason{columns:230px;column-gap:16px;margin-top:4px}
.im{position:relative;break-inside:avoid;margin-bottom:16px;border-radius:16px;overflow:hidden;background:var(--card);border:1px solid var(--line);cursor:zoom-in;
  transition:transform .35s var(--ease),box-shadow .35s var(--ease),border-color .3s;animation:rise .5s var(--ease) both}
.im:hover{transform:translateY(-4px);box-shadow:var(--sh2);border-color:var(--line2)}
.im .ph{display:block;width:100%;background:linear-gradient(90deg,var(--card2) 25%,var(--card3) 50%,var(--card2) 75%);background-size:200% 100%;animation:shimmer 1.3s linear infinite}
.im img{display:block;width:100%;height:auto;opacity:0;transition:opacity .5s,transform .6s var(--ease)}
.im img.in{opacity:1}
.im:hover img{transform:scale(1.04)}
.im .ov2{position:absolute;inset:auto 0 0 0;padding:34px 12px 12px;background:linear-gradient(transparent,rgba(5,5,10,.92));display:flex;align-items:flex-end;gap:10px;
  opacity:0;transform:translateY(8px);transition:.3s var(--ease)}
.im:hover .ov2,.im.feita .ov2{opacity:1;transform:none}
.im .ov2 div{flex:1;min-width:0}
.im .ov2 b{display:block;font-size:13px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.im .ov2 small{display:block;font-size:11.5px;color:#c9c3e6;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bimg{flex:none;display:flex;align-items:center;gap:6px;padding:8px 12px;border-radius:11px;background:var(--grad);color:#fff;font-weight:700;font-size:12.5px;
  box-shadow:0 8px 18px -8px rgba(217,70,239,.9);transition:transform .15s,filter .2s}
.bimg:hover{filter:brightness(1.1);transform:translateY(-1px)}
.bimg svg{width:15px;height:15px}
.bimg.ok{background:rgba(52,211,153,.18);color:#6ee7b7;box-shadow:none}
.bimg[disabled]{opacity:.7;pointer-events:none}
.bimg .spin{width:13px;height:13px;border-width:2px}
.imgfonte{color:var(--mute2);font-size:12px;text-align:center;margin-top:18px}
/* visualizador */
.lbx{position:fixed;inset:0;z-index:55;background:rgba(4,4,9,.9);backdrop-filter:blur(10px);display:grid;grid-template-rows:1fr auto;animation:fade .25s}
.lbx .area{position:relative;display:grid;place-items:center;padding:30px 90px 10px;min-height:0}
.lbx .area img{max-width:100%;max-height:calc(100vh - 150px);border-radius:14px;box-shadow:0 30px 80px rgba(0,0,0,.8);animation:modal .35s var(--ease);object-fit:contain}
.lbx .nav2{position:absolute;top:50%;transform:translateY(-50%);width:52px;height:52px;border-radius:50%;background:rgba(30,28,48,.8);border:1px solid var(--line2);display:grid;place-items:center;transition:.2s}
.lbx .nav2:hover{background:var(--card3);transform:translateY(-50%) scale(1.08)}
.lbx .nav2.e{left:22px}.lbx .nav2.d{right:22px}
.lbx .fx{position:absolute;top:18px;right:22px;width:44px;height:44px;border-radius:50%;background:rgba(30,28,48,.8);border:1px solid var(--line2);display:grid;place-items:center}
.lbx .bar2{display:flex;align-items:center;gap:14px;padding:16px 28px 22px;max-width:1100px;width:100%;margin:0 auto}
.lbx .bar2 div{flex:1;min-width:0}
.lbx .bar2 b{display:block;font-size:16px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.lbx .bar2 small{color:var(--muted)}
.lbx .bimg{padding:13px 22px;font-size:15px;border-radius:14px}

/* janela de destino */
.ov{position:fixed;inset:0;z-index:50;background:rgba(4,4,9,.72);backdrop-filter:blur(8px);display:grid;place-items:center;animation:fade .3s}
.ov.sai{opacity:0;transition:opacity .25s}
.modal{width:min(600px,92vw);max-height:88vh;display:flex;flex-direction:column;border-radius:26px;background:var(--card);border:1px solid var(--line2);box-shadow:0 40px 90px -20px rgba(0,0,0,.95);animation:modal .45s var(--ease)}
@keyframes modal{from{opacity:0;transform:translateY(26px) scale(.96)}}
.mh{display:flex;gap:16px;align-items:center;padding:26px 28px 6px}
.mh .mi{width:54px;height:54px;border-radius:16px;background:var(--grad);display:grid;place-items:center;flex:none;box-shadow:0 12px 26px -10px rgba(217,70,239,.8)}
.mh .mi svg{width:28px;height:28px;stroke:#fff}
.mh h2{font-size:22px;letter-spacing:-.4px}
.mb{overflow:auto;padding:12px 24px 6px 28px}
.mb .lb{font-size:11px;letter-spacing:1px;text-transform:uppercase;color:var(--mute2);font-weight:700;margin:14px 2px 8px}
.op{width:100%;display:flex;gap:13px;align-items:center;padding:13px 14px;border-radius:16px;background:var(--card2);border:1.5px solid var(--line);margin-bottom:9px;text-align:left;transition:.25s var(--ease)}
.op:hover{border-color:var(--line2);background:var(--card3);transform:translateX(3px)}
.op .ic{width:42px;height:42px;border-radius:12px;background:var(--card3);display:grid;place-items:center;color:#c4b5fd;flex:none}
.op.usb .ic{color:var(--ok);background:rgba(52,211,153,.12)}
.op b{display:block;font-size:15px}
.op small{display:block;color:var(--muted);font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.op>div{flex:1;min-width:0}
.op .rd{width:22px;height:22px;border-radius:50%;border:2px solid var(--line2);flex:none;display:grid;place-items:center;transition:.25s}
.op.sel{border-color:#a78bfa;background:linear-gradient(90deg,rgba(124,92,255,.16),rgba(217,70,239,.08))}
.op.sel .rd{border-color:transparent;background:var(--grad)}
.op.sel .rd::after{content:"";width:8px;height:8px;border-radius:50%;background:#fff;animation:pop .35s var(--ease)}
.op.novo{animation:novo 1.2s var(--ease)}
@keyframes novo{0%{box-shadow:0 0 0 0 rgba(52,211,153,.7)}100%{box-shadow:0 0 0 16px rgba(52,211,153,0)}}
.esperando{display:flex;align-items:center;gap:12px;padding:15px 16px;border-radius:16px;border:1.5px dashed var(--line2);color:var(--muted);margin-bottom:9px;font-size:13.5px}
.radar{position:relative;width:22px;height:22px;flex:none}
.radar i{position:absolute;inset:6px;border-radius:50%;background:#a78bfa}
.radar i:nth-child(2),.radar i:nth-child(3){inset:0;background:none;border:2px solid #a78bfa;animation:radar 1.8s ease-out infinite}
.radar i:nth-child(3){animation-delay:.9s}
@keyframes radar{from{transform:scale(.4);opacity:1}to{transform:scale(1.5);opacity:0}}
.mf{display:flex;gap:10px;padding:16px 28px 26px}
.mf .btn{flex:1}.mf .btn.sec{flex:none;width:140px}

/* avisos */
.toasts{position:fixed;top:18px;left:calc(262px + 50%);transform:translateX(calc(-50% - 131px));z-index:60;display:flex;flex-direction:column;gap:10px;align-items:center}
.toast{width:min(500px,90vw);display:flex;gap:14px;align-items:center;padding:15px 16px;border-radius:20px;background:rgba(26,24,41,.92);border:1px solid var(--line2);
  box-shadow:0 30px 60px -20px rgba(0,0,0,.95);backdrop-filter:blur(18px);animation:tin .5s var(--ease)}
@keyframes tin{from{opacity:0;transform:translateY(-30px) scale(.95)}}
.toast.out{animation:tout .3s ease forwards}
@keyframes tout{to{opacity:0;transform:translateY(-20px) scale(.97)}}
.toast .ic{width:44px;height:44px;border-radius:13px;display:grid;place-items:center;flex:none;background:rgba(52,211,153,.14);color:var(--ok)}
.toast .ic.err{background:rgba(251,113,133,.14);color:var(--bad)}
.toast>div{flex:1;min-width:0}
.toast b{display:block}
.toast small{display:block;color:var(--muted);font-size:12.5px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.toast .tb{display:flex;gap:8px;margin-top:10px}
.toast .tb .btn{padding:8px 14px;font-size:13px}
.toast .x{color:var(--mute2);padding:4px}
.toast .x:hover{color:var(--text)}

/* abertura */
#splash{position:fixed;inset:0;z-index:100;display:grid;place-items:center;background:radial-gradient(900px 600px at 20% 10%,rgba(124,92,255,.22),transparent 60%),radial-gradient(800px 600px at 85% 90%,rgba(255,106,61,.14),transparent 60%),#07070d;transition:opacity .6s ease,transform .6s ease}
#splash.sai{opacity:0;transform:scale(1.04);pointer-events:none}
.sc{display:flex;flex-direction:column;align-items:center;text-align:center;animation:rise .9s var(--ease) both}
.slogo{position:relative;width:132px;height:132px;display:grid;place-items:center;margin-bottom:30px}
.slogo .anel{position:absolute;inset:0;border-radius:38px;background:conic-gradient(from 0deg,#7c5cff,#d946ef,#ff6a3d,#7c5cff);animation:spin 3.2s linear infinite}
.slogo .anel::after{content:"";position:absolute;inset:3px;border-radius:35px;background:#0b0a14}
.slogo .pulso{position:absolute;inset:-8px;border-radius:46px;border:2px solid rgba(217,70,239,.45);animation:pul 2.4s ease-out infinite}
.slogo .pulso.b{animation-delay:1.2s}
@keyframes pul{0%{transform:scale(.9);opacity:.8}100%{transform:scale(1.5);opacity:0}}
.slogo img{position:relative;width:104px;height:104px;filter:drop-shadow(0 18px 40px rgba(217,70,239,.55));animation:flut 3s ease-in-out infinite}
@keyframes flut{50%{transform:translateY(-6px)}}
#splash h1{font-size:48px;margin:0}
#splash .sub{margin-top:4px;letter-spacing:.3px}
.sbar{width:min(420px,78vw);margin-top:36px}
.sbar .trilho{height:6px;border-radius:99px;background:rgba(160,150,210,.16);overflow:hidden}
.sbar .trilho i{display:block;height:100%;width:0;border-radius:99px;background:var(--grad);box-shadow:0 0 18px rgba(217,70,239,.7);transition:width .4s var(--ease)}
.sbar .info{display:flex;justify-content:space-between;margin-top:12px;font-size:13px;color:var(--muted)}
.sbar .info b{color:var(--text);font-variant-numeric:tabular-nums}
.serro{display:none;margin-top:24px;max-width:460px;padding:14px 18px;border:1px solid rgba(251,113,133,.5);background:rgba(251,113,133,.1);color:#fecdd3;border-radius:14px}
.seq{position:fixed;left:0;right:0;bottom:0;height:30vh;display:flex;gap:9px;align-items:flex-end;justify-content:center;opacity:.35;-webkit-mask-image:linear-gradient(to top,#000,transparent);mask-image:linear-gradient(to top,#000,transparent);pointer-events:none}
.seq i{width:12px;border-radius:6px 6px 0 0;background:linear-gradient(to top,rgba(217,70,239,0),rgba(217,70,239,.7));transform-origin:bottom;animation:eq 2.4s ease-in-out infinite}

@media(max-width:980px){body{grid-template-columns:84px 1fr}aside .brand div,nav button span,.sidecard,.pill span,.ver,.badge{display:none}
  .dock,.toasts{left:calc(84px + 50%);transform:translateX(calc(-50% - 42px));width:calc(100vw - 120px)}.dock.esc{transform:translate(calc(-50% - 42px),140%)}}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important}}
</style>
</head>
<body>
<div class="orbs"><i></i><i></i><i></i></div><div class="noise"></div>

<aside>
  <div class="brand"><img class="lg" src="/logo.svg" alt=""><div><b>Baixador</b><small>Músicas, vídeos e fontes</small></div></div>
  <nav>
    <button data-v="videos" class="on"><svg class="i" viewBox="0 0 24 24"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg><span>Músicas e vídeos</span></button>
    <button data-v="imagens"><svg class="i" viewBox="0 0 24 24"><rect x="3" y="3" width="18" height="18" rx="4"/><circle cx="8.5" cy="9" r="1.8"/><path d="M21 15l-5-5-9 9"/></svg><span>Imagens</span></button>
    <button data-v="fontes"><svg class="i" viewBox="0 0 24 24"><path d="M4 20l5-14h2l5 14M6.5 14h7"/><path d="M17 20v-6.5a2.5 2.5 0 015 0V20M17 16.5h5"/></svg><span>Fontes</span></button>
    <button data-v="downloads"><svg class="i" viewBox="0 0 24 24"><path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 21h14"/></svg><span>Downloads</span><em class="badge zero" id="badge">0</em></button>
  </nav>
  <div class="sp"></div>
  <div class="sidecard">
    <div class="lb">Salvando em</div>
    <div class="dest"><div class="ic" id="dIc"></div><div><b id="dNome">…</b><small id="dSub"></small></div></div>
    <button class="btn-ghost" id="dTrocar">Trocar local</button>
  </div>
  <div class="appst" id="appst"><span class="spin"></span><span>Instalando o aplicativo Baixador (só uma vez)…</span></div>
  <div class="pill" id="pill"><i></i><span id="pillT">Nenhum pendrive conectado</span></div>
  <div class="ver">Baixador __VERSAO__</div>
</aside>

<main id="main"><div class="wrap">
  <section id="v-videos" class="on">
    <div class="eyebrow">Baixar</div>
    <h1>O que você quer <span class="grad" id="hWord">ouvir</span> hoje?</h1>
    <p class="sub">Procure pelo nome ou cole o link do YouTube. Escolha, clique em baixar e pronto.</p>
    <div class="seg" id="segModo"><span class="ind"></span>
      <button data-m="nome" class="on"><svg class="i" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>Procurar pelo nome</button>
      <button data-m="link"><svg class="i" viewBox="0 0 24 24"><path d="M10 13a5 5 0 007.5.5l3-3a5 5 0 00-7-7l-1.7 1.7"/><path d="M14 11a5 5 0 00-7.5-.5l-3 3a5 5 0 007 7l1.7-1.7"/></svg>Baixar pelo link</button>
    </div>
    <div class="search" id="sBox">
      <svg class="i" viewBox="0 0 24 24" id="sIc"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>
      <input id="q" autocomplete="off" spellcheck="false" placeholder="Exemplo: Roberto Carlos Detalhes">
      <button class="btn sec" id="bColar" hidden><svg class="i" viewBox="0 0 24 24"><rect x="8" y="3" width="8" height="4" rx="1"/><path d="M16 5h2a2 2 0 012 2v12a2 2 0 01-2 2H6a2 2 0 01-2-2V7a2 2 0 012-2h2"/></svg>Colar</button>
      <button class="btn pri" id="bBuscar">Procurar</button>
    </div>
    <div class="guia aviso" id="guia"><span class="gi" id="gIc"></span><span id="gTx">Escolha para onde vão os arquivos baixados.</span></div>
    <div class="rhead"><h2 id="rTit">Clique no que você quer</h2><small id="rInfo"></small></div>
    <div id="res"></div>
    <div class="pag" id="pag"></div>
  </section>

  <section id="v-imagens">
    <div class="eyebrow">Imagens</div>
    <h1>Encontre a <span class="grad">imagem</span> perfeita</h1>
    <p class="sub">Pesquise, passe por várias páginas de resultados e baixe com um clique. Vai para a mesma pasta das músicas.</p>
    <div class="search" style="margin-top:22px"><svg class="i" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>
      <input id="iq" autocomplete="off" spellcheck="false" placeholder="Exemplo: pôr do sol na praia, gato fofo, paisagem de inverno">
      <button class="btn pri" id="iBuscar">Pesquisar</button></div>
    <div class="guia info" id="iGuia" style="display:none"></div>
    <div class="rhead"><h2 id="iTit">Resultados</h2><small id="iInfo"></small></div>
    <div id="ires"></div>
    <div class="pag" id="ipag"></div>
    <p class="imgfonte" id="iFonte"></p>
  </section>

  <section id="v-fontes">
    <div class="eyebrow">Fontes</div>
    <h1>Fontes para <span class="grad">instalar</span> com um clique</h1>
    <p class="sub">Procure pelo nome ou navegue por todas as categorias. Elas vêm do site dafont.com.</p>
    <div class="frow">
      <div class="search"><svg class="i" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.3-4.3"/></svg>
        <input id="fq" autocomplete="off" spellcheck="false" placeholder="Exemplo: medieval, old english, blackletter">
        <button class="btn pri" id="fBuscar">Procurar</button></div>
    </div>
    <div class="cats" id="fGrupos"></div>
    <div class="subs" id="fSubs"></div>
    <p class="nota">Cada fonte tem a sua licença (aparece embaixo do nome). Confira antes de usar em trabalhos que vão ser vendidos.</p>
    <div class="rhead"><h2 id="fTit">Fontes</h2><small id="fInfo"></small></div>
    <div id="fres"></div>
    <div class="pag" id="fpag"></div>
  </section>

  <section id="v-downloads">
    <div class="eyebrow">Downloads</div>
    <h1>Seus <span class="grad">downloads</span></h1>
    <p class="sub">Pode continuar procurando enquanto baixa: tudo entra na fila e baixa sozinho.</p>
    <div class="rhead"><h2 id="tTit">Nesta sessão</h2><button class="btn sec" id="tLimpar" style="padding:8px 14px;font-size:13px">Limpar concluídos</button></div>
    <div id="tres"></div>
  </section>
</div></main>

<div class="dock vaziad" id="dock">
  <div class="dt" id="kT"><span class="ph"><svg class="i" viewBox="0 0 24 24"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg></span></div>
  <div class="di"><small>Escolhido</small><b id="kTit">Nada escolhido ainda</b><span id="kSub">Clique em um resultado para escolher</span></div>
  <div class="fmt" id="fmt"><span class="ind"></span>
    <button data-f="mp3" class="on"><svg class="i" viewBox="0 0 24 24"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>Música</button>
    <button data-f="mp4"><svg class="i" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M10 9.5v5l4.5-2.5z"/></svg>Vídeo</button>
  </div>
  <button class="btn pri lg go" id="bBaixar"><svg class="i" viewBox="0 0 24 24"><path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 21h14"/></svg>Baixar agora</button>
  <div class="mini"><i id="kBar"></i></div>
</div>

<div class="toasts" id="toasts"></div>
<div id="ovRoot"></div>

<div id="splash"><div class="seq" id="seq"></div>
  <div class="sc">
    <div class="slogo"><span class="pulso"></span><span class="pulso b"></span><span class="anel"></span><img src="/logo.svg" alt=""></div>
    <h1 class="grad">Baixador</h1><div class="sub">Músicas, vídeos e fontes</div>
    <div class="sbar"><div class="trilho"><i id="sBar"></i></div><div class="info"><span id="sMsg">Iniciando</span><b id="sPct">0%</b></div></div>
    <div class="serro" id="sErro"></div>
  </div>
</div>

<script>
const T = "__TOKEN__";
const $ = s => document.querySelector(s);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
const sleep = ms => new Promise(r => setTimeout(r, ms));
async function api(path, body) {
  const o = {headers: {"X-T": T}};
  if (body !== undefined) { o.method = "POST"; o.body = JSON.stringify(body); o.headers["Content-Type"] = "application/json"; }
  const r = await fetch(path, o);
  let j = {}; try { j = await r.json(); } catch (e) {}
  if (!r.ok && !j.erro) j.erro = "Falha de comunicação (" + r.status + ")";
  return j;
}
const IC = {
  usb: '<svg class="i" viewBox="0 0 24 24"><rect x="7" y="9" width="10" height="13" rx="2.5"/><path d="M9 9V3h6v6M11 5.5v1M13 5.5v1"/></svg>',
  pasta: '<svg class="i" viewBox="0 0 24 24"><path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/></svg>',
  pastaMais: '<svg class="i" viewBox="0 0 24 24"><path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/><path d="M12 10.5v5M9.5 13h5"/></svg>',
  musica: '<svg class="i" viewBox="0 0 24 24"><path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/></svg>',
  aviso: '<svg class="i" viewBox="0 0 24 24"><path d="M12 8v4M12 16h.01"/><circle cx="12" cy="12" r="9"/></svg>',
  info: '<svg class="i" viewBox="0 0 24 24"><path d="M21 12a9 9 0 11-3-6.7L21 8"/><path d="M21 3v5h-5"/></svg>',
  ok: '<svg class="i" viewBox="0 0 24 24"><path d="M20 6L9 17l-5-5"/></svg>',
  erro: '<svg class="i" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9"/><path d="M15 9l-6 6M9 9l6 6"/></svg>',
  baixar: '<svg class="i" viewBox="0 0 24 24"><path d="M12 3v12M7 10l5 5 5-5"/><path d="M5 21h14"/></svg>',
  mudo: '<svg class="i" viewBox="0 0 24 24"><path d="M11 5L6 9H2v6h4l5 4z"/><path d="M23 9l-6 6M17 9l6 6"/></svg>',
  play: '<svg class="i" viewBox="0 0 24 24"><rect x="3" y="5" width="18" height="14" rx="3"/><path d="M10 9.5v5l4.5-2.5z"/></svg>',
  x: '<svg class="i" viewBox="0 0 24 24"><path d="M18 6L6 18M6 6l12 12"/></svg>',
};

/* ---------------- estado ---------------- */
const S = {modo: "nome", formato: "mp3", destino: null, pendrives: [], ffmpeg: true, busca: null, pagina: 1,
  escolhido: null, ocupadoBusca: false, tarefas: [], vistas: {}, modal: null, fontes: {modo: "cat", q: "", p: 1, total: 1, cat: "", grupos: [], iniciado: false}, appAvisado: false};
const POR_PAG = 12;

/* ---------------- abertura ---------------- */
(function () {
  const seq = $("#seq");
  for (let i = 0; i < 40; i++) { const b = document.createElement("i"); b.style.height = (25 + Math.random() * 75) + "%";
    b.style.animationDelay = (-Math.random() * 2.4) + "s"; b.style.animationDuration = (1.8 + Math.random() * 1.6) + "s"; seq.appendChild(b); }
})();
async function abertura() {
  let mostrado = 0;
  while (true) {
    let e; try { e = await api("/api/estado"); } catch (x) { await sleep(400); continue; }
    if (e.erro) { $("#sErro").style.display = "block"; $("#sErro").textContent = e.erro; $("#sMsg").textContent = "Não foi possível iniciar"; return; }
    mostrado = Math.max(mostrado, e.pct || 0);
    $("#sBar").style.width = mostrado + "%"; $("#sPct").textContent = Math.round(mostrado) + "%";
    if (e.msg && $("#sMsg").textContent !== e.msg) $("#sMsg").textContent = e.msg;
    if (e.pronto) { S.ffmpeg = e.ffmpeg; break; }
    await sleep(250);
  }
  await sleep(350);
  $("#splash").classList.add("sai");
  setTimeout(() => $("#splash").remove(), 700);
  await atualizarDestinos(true);
  if (!S.ffmpeg) guia("Atenção: o conversor de áudio (ffmpeg) não foi encontrado. Feche e abra o Baixador de novo.", "erro");
  abrirSeletor(true);
  setInterval(atualizarDestinos, 1500);
  setInterval(() => api("/api/ping"), 15000);
  laçoTarefas();
}

/* ---------------- navegação ---------------- */
function irPara(v) {
  document.querySelectorAll("nav button").forEach(b => b.classList.toggle("on", b.dataset.v === v));
  document.querySelectorAll("section").forEach(s => s.classList.toggle("on", s.id === "v-" + v));
  $("#dock").classList.toggle("esc", v !== "videos");
  $("#main").scrollTop = 0;
  pararPrevia();
  if (v === "fontes" && !S.fontes.iniciado) { S.fontes.iniciado = true; iniciarFontes(); }
  if (v === "downloads") desenharTarefas();
  if (v === "imagens") { if (!IM.busca) imgVazio(); setTimeout(() => $("#iq").focus(), 50); }
}
document.querySelectorAll("nav button").forEach(b => b.onclick = () => irPara(b.dataset.v));

/* ---------------- faixa de orientação ---------------- */
let guiaUlt = "";
function guia(texto, tipo = "aviso") {
  const g = $("#guia");
  g.className = "guia " + tipo; $("#gIc").innerHTML = IC[tipo] || IC.aviso;
  $("#gTx").textContent = texto;
  void g.offsetWidth; g.classList.add("troca");
  guiaUlt = texto;
}

/* ---------------- alternadores animados ---------------- */
function moverInd(box) {
  const on = box.querySelector("button.on"), ind = box.querySelector(".ind");
  if (!on || !ind) return;
  ind.style.width = on.offsetWidth + "px";
  ind.style.transform = `translateX(${on.offsetLeft - 5 + (box.id === "fmt" ? 1 : 0)}px)`;
}
function mudarModo(m, avisar = true) {
  S.modo = m;
  document.querySelectorAll("#segModo button").forEach(b => b.classList.toggle("on", b.dataset.m === m));
  moverInd($("#segModo"));
  const q = $("#q");
  $("#bColar").hidden = m !== "link";
  $("#bBuscar").textContent = m === "nome" ? "Procurar" : "Verificar";
  q.placeholder = m === "nome" ? "Exemplo: Roberto Carlos Detalhes" : "Cole aqui o link (começa com https://)";
  $("#rTit").textContent = m === "nome" ? "Clique no que você quer" : "Confira se é o vídeo certo";
  if (avisar) {
    q.value = ""; S.busca = null; vazio(m === "nome" ? "Os resultados da busca vão aparecer aqui." : "O vídeo do link vai aparecer aqui.");
    guia(m === "nome" ? "Digite o nome e clique em PROCURAR (ou aperte Enter)." : "Clique no botão COLAR para colar o link copiado.");
    q.focus();
  }
}
document.querySelectorAll("#segModo button").forEach(b => b.onclick = () => mudarModo(b.dataset.m));
function mudarFormato(f, salvar = true) {
  S.formato = f;
  document.querySelectorAll("#fmt button").forEach(b => b.classList.toggle("on", b.dataset.f === f));
  moverInd($("#fmt"));
  $("#hWord").textContent = f === "mp3" ? "ouvir" : "assistir";
  if (salvar) api("/api/config", {formato: f});
}
document.querySelectorAll("#fmt button").forEach(b => b.onclick = () => mudarFormato(b.dataset.f));
window.addEventListener("resize", () => { moverInd($("#segModo")); moverInd($("#fmt")); });

/* ---------------- destino e pendrives ---------------- */
function tamTxt(n) { return n; }
async function atualizarDestinos(primeira) {
  let d; try { d = await api("/api/destinos"); } catch (e) { return; }
  if (d.erro) return;
  const antes = new Set(S.pendrives.map(p => p.letra)), agora = new Set(d.pendrives.map(p => p.letra));
  const novos = primeira ? [] : d.pendrives.filter(p => !antes.has(p.letra));
  const sumidos = primeira ? [] : S.pendrives.filter(p => !agora.has(p.letra));
  S.pendrives = d.pendrives; S.destino = d.destino; S.musicas = d.musicas;
  if (primeira) { mudarFormato(d.formato || "mp3", false); }
  desenharDestino();
  const n = d.pendrives.length;
  $("#pill").classList.toggle("on", n > 0);
  $("#pillT").textContent = n ? `${n} pendrive${n > 1 ? "s" : ""} conectado${n > 1 ? "s" : ""}` : "Nenhum pendrive conectado";
  $("#appst").classList.toggle("on", d.app === "gerando");
  if (d.app === "pronto" && !S.appAvisado) {
    S.appAvisado = true;
    const t = toast(`<span class="ic"><img src="/logo.svg" style="width:30px;height:30px;border-radius:9px"></span><div><b>O Baixador agora é um aplicativo!</b><small>Fica no menu Iniciar e na Área de Trabalho. Não abre mais a tela preta.</small>
      <div class="tb"><button class="btn pri" data-a="abrir">Abrir o aplicativo agora</button><button class="btn sec" data-a="depois">Depois</button></div></div>`, {tempo: 0});
    t.querySelector('[data-a="depois"]').onclick = () => fecharToast(t);
    t.querySelector('[data-a="abrir"]').onclick = async () => {
      if (S.tarefas.some(x => ["fila", "baixando", "convertendo"].includes(x.estado))) { toastErro("Espere os downloads terminarem."); return; }
      const r = await api("/api/abrir_app", {});
      if (!r.erro) setTimeout(() => { try { window.close(); } catch (e) {} }, 500);
    };
  }
  if (d.atualizacao) {
    const u = d.atualizacao;
    if (!S.atuToast) {
      S.atuToast = toast(`<span class="ic"><img src="/logo.svg" style="width:30px;height:30px;border-radius:9px"></span><div><b>Nova versão ${esc(u.versao)} disponível</b><small>${esc(u.notas || "Melhorias e correções.")}</small>
        <div class="tb"><button class="btn pri" data-a="atu">Atualizar agora</button><button class="btn sec" data-a="dep">Depois</button></div></div>`, {tempo: 0});
      S.atuToast.querySelector('[data-a="dep"]').onclick = () => fecharToast(S.atuToast);
      S.atuToast.querySelector('[data-a="atu"]').onclick = async () => {
        if (S.tarefas.some(x => ["fila", "baixando", "convertendo"].includes(x.estado))) { toastErro("Espere os downloads terminarem."); return; }
        await api("/api/atualizar", {});
      };
    }
    const b = S.atuToast.querySelector('[data-a="atu"]');
    if (b && u.estado === "baixando") { b.disabled = true; b.innerHTML = `<span class="spin"></span>Baixando ${u.pct}%`; }
    else if (b && u.estado === "pronto") b.innerHTML = '<span class="spin"></span>Reabrindo…';
    else if (b && u.estado === "erro") { b.disabled = false; b.textContent = "Tentar de novo"; }
  }
  if (d.removido) guia(`O pendrive ${d.removido} foi removido. Voltei para a pasta Músicas.`, "erro");
  sumidos.forEach(p => document.querySelectorAll(`.toast[data-l="${CSS.escape(p.letra)}"]`).forEach(fecharToast));
  if (S.modal) {
    if (S.modal.sel && S.modal.sel.chave.startsWith("drive:") && !agora.has(S.modal.sel.path)) S.modal.sel = {chave: "musicas", path: S.musicas};
    if (novos.length) S.modal.sel = {chave: "drive:" + novos[0].letra, path: novos[0].letra};
    if (novos.length || sumidos.length) desenharOpcoes(novos[0] && novos[0].letra);
  } else novos.forEach(toastPendrive);
}
function desenharDestino() {
  const d = S.destino; if (!d) return;
  $("#dIc").innerHTML = d.tipo === "pendrive" ? IC.usb : IC.pasta;
  $("#dIc").classList.toggle("usb", d.tipo === "pendrive");
  $("#dNome").textContent = d.nome; $("#dSub").textContent = d.sub; $("#dSub").title = d.path;
}
$("#dTrocar").onclick = () => abrirSeletor(false);

function abrirSeletor(obrigatorio) {
  if (S.modal) return;
  pararPrevia();
  const d = S.destino || {tipo: "musicas", path: S.musicas};
  let sel;
  if (d.tipo === "pendrive") sel = {chave: "drive:" + S.pendrives.find(p => p.letra.slice(0, 2).toUpperCase() === d.path.slice(0, 2).toUpperCase())?.letra, path: d.path.length <= 3 ? d.path : d.path};
  else if (obrigatorio && S.pendrives.length) sel = {chave: "drive:" + S.pendrives[0].letra, path: S.pendrives[0].letra};
  else if (d.tipo === "musicas") sel = {chave: "musicas", path: S.musicas};
  else sel = {chave: "outra", path: d.path};
  S.modal = {obrigatorio, sel, outra: d.tipo === "outra" ? d.path : ""};
  $("#ovRoot").innerHTML = `<div class="ov" id="ov"><div class="modal" role="dialog">
    <div class="mh"><div class="mi">${IC.usb}</div><div><h2>Para onde vão as músicas?</h2><p class="sub">Se você conectar um pendrive agora, ele aparece aqui sozinho.</p></div></div>
    <div class="mb" id="opcoes"></div>
    <div class="mf">${obrigatorio ? "" : '<button class="btn sec" id="mCancel">Cancelar</button>'}<button class="btn pri lg" id="mOk">Continuar</button></div>
  </div></div>`;
  desenharOpcoes();
  $("#mOk").onclick = confirmarSeletor;
  if (!obrigatorio) { $("#mCancel").onclick = fecharSeletor; $("#ov").onclick = e => { if (e.target.id === "ov") fecharSeletor(); }; }
}
function desenharOpcoes(novo) {
  const m = S.modal; if (!m) return;
  const op = (chave, path, cls, ic, tit, sub) => `<button class="op ${cls} ${m.sel && m.sel.chave === chave ? "sel" : ""} ${novo && chave === "drive:" + novo ? "novo" : ""}" data-c="${esc(chave)}" data-p="${esc(path || "")}">
    <span class="ic">${ic}</span><div><b>${esc(tit)}</b><small>${esc(sub)}</small></div><span class="rd"></span></button>`;
  let h = '<div class="lb">Pendrives conectados</div>';
  if (S.pendrives.length) S.pendrives.forEach(p => h += op("drive:" + p.letra, p.letra, "usb", IC.usb, p.rotulo, p.sub));
  else h += '<div class="esperando"><span class="radar"><i></i><i></i><i></i></span>Aguardando um pendrive... conecte e ele aparece aqui.</div>';
  h += '<div class="lb">Outros locais</div>';
  h += op("musicas", S.musicas, "", IC.musica, "Pasta Músicas", S.musicas);
  h += op("outra", m.outra, "", IC.pastaMais, "Outra pasta...", m.outra || "Escolher uma pasta no computador");
  $("#opcoes").innerHTML = h;
  document.querySelectorAll("#opcoes .op").forEach(b => b.onclick = async () => {
    if (b.dataset.c === "outra") return pedirPasta();
    m.sel = {chave: b.dataset.c, path: b.dataset.p}; desenharOpcoes();
  });
}
async function pedirPasta() {
  const m = S.modal; if (!m) return;
  const r = await api("/api/escolher_pasta", {inicial: m.outra || (S.destino && S.destino.path) || ""});
  if (r.path && S.modal) { m.outra = r.path; m.sel = {chave: "outra", path: r.path}; desenharOpcoes(); }
}
async function confirmarSeletor() {
  const m = S.modal; if (!m || !m.sel) return;
  if (!m.sel.path) return pedirPasta();
  const r = await api("/api/config", {destino: m.sel.path});
  if (r.erro) { guia(r.erro, "erro"); return; }
  S.destino = r.destino; desenharDestino(); fecharSeletor();
  if (r.destino.tipo === "pendrive") guia(`Tudo certo! Os arquivos vão para o pendrive ${r.destino.nome}. Agora digite o nome da música e clique em PROCURAR.`, "ok");
  else guia("Tudo certo! Agora digite o nome da música e clique em PROCURAR.", "ok");
}
function fecharSeletor() {
  const ov = $("#ov"); S.modal = null;
  if (ov) { ov.classList.add("sai"); setTimeout(() => ov.remove(), 250); }
  if ($("#v-videos").classList.contains("on")) $("#q").focus();
}

/* ---------------- avisos (toasts) ---------------- */
function toast(html, {letra, tempo = 7000} = {}) {
  const t = document.createElement("div"); t.className = "toast"; t.innerHTML = html;
  if (letra) t.dataset.l = letra;
  $("#toasts").appendChild(t);
  const x = t.querySelector(".x"); if (x) x.onclick = () => fecharToast(t);
  if (tempo) setTimeout(() => fecharToast(t), tempo);
  return t;
}
function fecharToast(t) { if (!t || t.classList.contains("out")) return; t.classList.add("out"); setTimeout(() => t.remove(), 300); }
function toastPendrive(p) {
  const t = toast(`<span class="ic">${IC.usb}</span><div><b>Pendrive conectado</b><small>${esc(p.rotulo)} · ${esc(p.sub)}</small>
    <div class="tb"><button class="btn pri" data-a="usar">Usar este pendrive</button><button class="btn sec" data-a="nao">Agora não</button></div></div>`, {letra: p.letra, tempo: 20000});
  t.querySelector('[data-a="nao"]').onclick = () => fecharToast(t);
  t.querySelector('[data-a="usar"]').onclick = async () => {
    const r = await api("/api/config", {destino: p.letra});
    if (!r.erro) { S.destino = r.destino; desenharDestino(); guia(`Pronto! Os arquivos vão para o pendrive ${p.letra.slice(0, 2)}.`, "ok"); }
    fecharToast(t);
  };
}
function ding() {
  try {
    const c = new (window.AudioContext || window.webkitAudioContext)();
    [[880, 0], [1318.5, .12]].forEach(([f, d]) => { const o = c.createOscillator(), g = c.createGain(); o.type = "sine"; o.frequency.value = f;
      g.gain.setValueAtTime(0, c.currentTime + d); g.gain.linearRampToValueAtTime(.18, c.currentTime + d + .02); g.gain.exponentialRampToValueAtTime(.001, c.currentTime + d + .6);
      o.connect(g).connect(c.destination); o.start(c.currentTime + d); o.stop(c.currentTime + d + .65); });
  } catch (e) {}
}

/* ---------------- busca ---------------- */
function vazio(texto) {
  pararPrevia();
  $("#res").innerHTML = `<div class="vazio"><div class="eqv">${"<i></i>".repeat(7)}</div><b>${esc(texto)}</b><span>Dica: dá para procurar pelo nome do cantor e da música juntos.</span></div>`;
  document.querySelectorAll(".vazio .eqv i").forEach((i, k) => { i.style.animationDelay = (-k * .17) + "s"; i.style.height = (40 + (k * 37) % 60) + "%"; });
  $("#pag").innerHTML = ""; $("#rInfo").textContent = "";
}
function esqueleto(n = 8) {
  pararPrevia();
  $("#res").innerHTML = '<div class="grid">' + Array.from({length: n}, (_, i) => `<div class="skel" style="animation:rise .4s ${i * .04}s both"><div class="b" style="aspect-ratio:16/9"></div><div class="b" style="height:14px;margin:14px 4px 8px;width:85%"></div><div class="b" style="height:11px;margin:0 4px 6px;width:50%"></div></div>`).join("") + "</div>";
  $("#pag").innerHTML = "";
}
async function colar() {
  const r = await api("/api/colar");
  if (!r.texto) { guia("Não há nenhum link copiado. Copie o endereço do vídeo no YouTube e tente de novo.", "erro"); return; }
  $("#q").value = r.texto; buscar();
}
$("#bColar").onclick = colar;
$("#bBuscar").onclick = () => buscar();
$("#q").addEventListener("keydown", e => { if (e.key === "Enter") buscar(); });
function buscar() {
  if (S.ocupadoBusca || S.modal) return;
  let termo = $("#q").value.trim();
  if (!termo) { guia(S.modo === "nome" ? "Escreva primeiro na caixa de busca." : "Clique em COLAR para colocar o link copiado.", "erro"); $("#q").focus(); return; }
  const ehLink = /^(https?:\/\/|www\.)/i.test(termo);
  if (S.modo === "link" && !ehLink) { guia("Isso não parece um link. Um link começa com https://", "erro"); return; }
  S.busca = {termo, ehLink, res: [], fim: false, tok: {}};
  irPagina(1, true);
}
async function irPagina(p, nova = false) {
  const b = S.busca; if (!b || p < 1) return;
  if (S.ocupadoBusca) return;
  if (b.res.length >= p * POR_PAG || b.fim) { mostrarPagina(Math.min(p, Math.max(1, Math.ceil(b.res.length / POR_PAG)))); return; }
  S.ocupadoBusca = true; const bt = $("#bBuscar"); bt.disabled = true; bt.innerHTML = '<span class="spin"></span>' + (S.modo === "nome" ? "Procurando" : "Verificando");
  esqueleto(nova ? 8 : POR_PAG);
  guia(nova ? "Procurando... isso pode levar alguns segundos." : `Buscando mais resultados para a página ${p}...`, "info");
  const tok = b.tok;
  let r; try { r = await api(`/api/buscar?q=${encodeURIComponent(b.termo)}&n=${b.ehLink ? 10 : p * POR_PAG}`); } catch (e) { r = {erro: String(e)}; }
  S.ocupadoBusca = false; bt.disabled = false; bt.textContent = S.modo === "nome" ? "Procurar" : "Verificar";
  if (S.busca !== b || b.tok !== tok) return;
  if (r.erro) {
    if (p > 1 && b.res.length) { mostrarPagina(S.pagina); guia("Não consegui carregar a próxima página. Verifique a internet e tente de novo.", "erro"); return; }
    vazio("Não consegui procurar.");
    guia(b.ehLink ? "Esse link não funcionou. Confira se copiou o endereço inteiro do vídeo." : "Não deu para procurar. Verifique se a internet está funcionando e tente de novo.", "erro");
    return;
  }
  if (r.res.length >= b.res.length) b.res = r.res;
  b.fim = r.fim || b.ehLink;
  if (!b.res.length) { vazio("Não encontrei nada. Tente escrever de outro jeito."); guia("Não encontrei nada. Tente outro nome.", "erro"); return; }
  const ult = Math.max(1, Math.ceil(b.res.length / POR_PAG));
  if (p > ult) { mostrarPagina(ult); guia("Não há mais resultados. Esta é a última página.", "erro"); return; }
  mostrarPagina(p);
}
function hue(s) { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) % 360; return h; }
function mostrarPagina(p) {
  const b = S.busca; S.pagina = p; pararPrevia();
  const itens = b.res.slice((p - 1) * POR_PAG, p * POR_PAG);
  $("#res").innerHTML = '<div class="grid">' + itens.map((it, i) => `
    <div class="vc ${S.escolhido && S.escolhido.url === it.url ? "sel" : ""}" data-i="${(p - 1) * POR_PAG + i}" style="animation-delay:${i * 45}ms">
      <div class="thumb" style="--h:${hue(it.titulo)}"><span class="ph">${IC.musica}</span>
        ${it.mini ? `<img loading="lazy" src="${esc(it.mini)}" onload="this.classList.add('in')" onerror="this.remove()">` : ""}
        ${it.tempo ? `<span class="dur">${esc(it.tempo)}</span>` : ""}
        <span class="mudo">${IC.mudo}</span><span class="pv"><i></i></span><span class="load"></span>
        <span class="check">${IC.ok}</span></div>
      <div class="meta"><div><div class="tt" title="${esc(it.titulo)}">${esc(it.titulo)}</div>
        <div class="ch">${esc([it.canal, it.views && it.views + " visualizações"].filter(Boolean).join(" · "))}</div></div>
        <button class="quick" title="Baixar agora">${IC.baixar}</button></div>
    </div>`).join("") + "</div>";
  document.querySelectorAll("#res .vc").forEach(c => {
    const it = b.res[+c.dataset.i];
    c.onclick = e => { if (e.target.closest(".quick")) { escolher(it, c); baixar(); return; } escolher(it, c); };
    c.onmouseenter = () => agendarPrevia(c, it);
    c.onmouseleave = () => { if (PV.card === c || PV.timer) pararPrevia(); };
  });
  const total = b.res.length;
  $("#rInfo").textContent = b.ehLink ? "" : `Página ${p} · ${total}${b.fim ? "" : "+"} resultados`;
  paginas($("#pag"), p, Math.ceil(total / POR_PAG) + (b.fim ? 0 : 1), n => { irPagina(n); $("#main").scrollTo({top: 0}); });
  if (!b.ehLink && !S.escolhido) guia(`Encontrei! Passe o mouse para ver uma prévia e clique no que você quer baixar.`, "aviso");
  else if (b.ehLink) guia("Confira se é o vídeo certo e clique nele para escolher.", "aviso");
}
function paginas(el, p, total, ir) {
  if (total <= 1) { el.innerHTML = ""; return; }
  const nums = new Set([1, total, p - 1, p, p + 1]); if (p <= 3) [2, 3, 4].forEach(n => nums.add(n)); if (p >= total - 2) [total - 3, total - 2, total - 1].forEach(n => nums.add(n));
  const lista = [...nums].filter(n => n >= 1 && n <= total).sort((a, b) => a - b);
  let h = `<button data-n="${p - 1}" ${p <= 1 ? "disabled" : ""}>‹ Anterior</button>`, ant = 0;
  lista.forEach(n => { if (n - ant > 1) h += "<span>…</span>"; h += `<button data-n="${n}" class="${n === p ? "on" : ""}">${n}</button>`; ant = n; });
  h += `<button data-n="${p + 1}" ${p >= total ? "disabled" : ""}>Próxima ›</button>`;
  el.innerHTML = h;
  el.querySelectorAll("button").forEach(b => b.onclick = () => { const n = +b.dataset.n; if (n !== p) ir(n); });
}
function escolher(it, card) {
  S.escolhido = it;
  document.querySelectorAll("#res .vc.sel").forEach(c => c.classList.remove("sel"));
  if (card) card.classList.add("sel");
  const dock = $("#dock");
  dock.classList.remove("vaziad", "troca"); void dock.offsetWidth; dock.classList.add("troca");
  $("#kT").innerHTML = it.mini ? `<img src="${esc(it.mini)}">` : `<span class="ph">${IC.musica}</span>`;
  $("#kTit").textContent = it.titulo; $("#kSub").textContent = [it.canal, it.tempo].filter(Boolean).join(" · ");
  const go = $("#bBaixar"); go.classList.remove("brilha"); void go.offsetWidth; go.classList.add("brilha");
  guia(`Escolhido! Agora clique em BAIXAR AGORA (${S.formato === "mp3" ? "só a música" : "vídeo com som"}).`, "ok");
}

/* ---------------- prévia ao passar o mouse ---------------- */
const PV = {timer: null, card: null, video: null, srcs: {}};
function agendarPrevia(card, it) {
  pararPrevia();
  PV.timer = setTimeout(() => iniciarPrevia(card, it), 450);
}
async function iniciarPrevia(card, it) {
  PV.timer = null; PV.card = card;
  const th = card.querySelector(".thumb"); th.classList.add("carregando");
  let src = PV.srcs[it.url];
  if (!src) {
    const r = await api("/api/previa?u=" + encodeURIComponent(it.url));
    if (r.src) PV.srcs[it.url] = src = r.src;
  }
  if (PV.card !== card || !src) { th.classList.remove("carregando"); return; }
  const v = document.createElement("video");
  v.muted = true; v.playsInline = true; v.autoplay = true; v.preload = "auto"; v.src = src;
  const barra = th.querySelector(".pv i"), dur = th.querySelector(".dur");
  v.addEventListener("playing", () => { th.classList.remove("carregando"); th.classList.add("tocando"); v.classList.add("in"); });
  v.addEventListener("timeupdate", () => {
    const total = it.dur || v.duration || 0; if (!total) return;
    barra.style.width = Math.min(100, v.currentTime / total * 100) + "%";
    if (dur) { const r = Math.max(0, total - v.currentTime); dur.textContent = Math.floor(r / 60) + ":" + String(Math.floor(r % 60)).padStart(2, "0"); }
  });
  v.addEventListener("error", () => { th.classList.remove("carregando"); });
  th.insertBefore(v, th.querySelector(".dur"));
  PV.video = v;
}
function pararPrevia() {
  clearTimeout(PV.timer); PV.timer = null;
  if (PV.card) {
    const th = PV.card.querySelector(".thumb");
    th.classList.remove("tocando", "carregando");
    const it = S.busca && S.busca.res[+PV.card.dataset.i];
    const dur = th.querySelector(".dur"); if (dur && it) dur.textContent = it.tempo;
  }
  if (PV.video) { const v = PV.video; v.classList.remove("in"); setTimeout(() => { v.pause(); v.removeAttribute("src"); v.load(); v.remove(); }, 300); }
  PV.card = null; PV.video = null;
}

/* ---------------- download ---------------- */
$("#bBaixar").onclick = () => baixar();
async function baixar() {
  if (S.modal) return;
  const it = S.escolhido;
  if (!it) { guia("Primeiro faça a busca e clique no que você quer baixar.", "erro"); $("#q").focus(); return; }
  if (S.formato === "mp3" && !S.ffmpeg) { guia("Para baixar música é preciso o conversor de áudio. Feche e abra o Baixador de novo.", "erro"); return; }
  const r = await api("/api/baixar", {url: it.url, titulo: it.titulo, mini: it.mini, canal: it.canal, formato: S.formato});
  if (r.erro) { guia(r.erro, "erro"); return; }
  S.vistas[r.tarefa.id] = "fila";
  S.tarefas.push(r.tarefa);
  const b = $("#badge"); b.classList.remove("bump"); void b.offsetWidth; b.classList.add("bump");
  guia("Baixando... pode continuar procurando outras músicas enquanto isso.", "info");
  $("#dock").classList.add("bx");
  laçoTarefas(true);
}
let laçoAtivo = false, laçoAcordar = null;
async function laçoTarefas(acordar) {
  if (acordar && laçoAcordar) { laçoAcordar(); return; }
  if (laçoAtivo) return; laçoAtivo = true;
  while (true) {
    let r; try { r = await api("/api/tarefas"); } catch (e) { r = null; }
    if (r && r.tarefas) { S.tarefas = r.tarefas; processarTarefas(); }
    const ativo = S.tarefas.some(t => ["fila", "baixando", "convertendo"].includes(t.estado));
    await new Promise(res => { laçoAcordar = res; setTimeout(res, ativo ? 600 : 3000); });
    laçoAcordar = null;
  }
}
function processarTarefas() {
  const ativos = S.tarefas.filter(t => ["fila", "baixando", "convertendo"].includes(t.estado));
  const b = $("#badge"); b.textContent = ativos.length; b.classList.toggle("zero", !ativos.length);
  const cur = ativos.find(t => t.estado !== "fila");
  $("#dock").classList.toggle("bx", !!ativos.length);
  $("#kBar").style.width = (cur ? cur.pct : 0) + "%";
  for (const t of S.tarefas) {
    const antes = S.vistas[t.id];
    if (antes === t.estado) continue;
    S.vistas[t.id] = t.estado;
    if (!antes) continue;
    if (t.estado === "pronto") {
      const tipo = t.formato === "mp3" ? "A música" : "O vídeo";
      guia(`✔  PRONTO!  ${tipo} foi baixado com sucesso.`, "ok"); ding();
      const tt = toast(`<span class="ic">${IC.ok}</span><div><b>${tipo} está pronta!</b><small>${esc(t.arquivo)} · ${esc(t.destino_nome)}</small>
        <div class="tb"><button class="btn sec" data-a="abrir">Abrir a pasta</button></div></div><button class="x">${IC.x}</button>`.replace("pronta!", t.formato === "mp3" ? "pronta!" : "pronto!"), {tempo: 9000});
      tt.querySelector('[data-a="abrir"]').onclick = () => { api("/api/abrir", {path: t.caminho || t.destino, selecionar: !!t.caminho}); fecharToast(tt); };
      atualizarDestinos();
    } else if (t.estado === "erro") {
      guia("Não deu certo. Verifique a internet e tente de novo.", "erro");
      toast(`<span class="ic err">${IC.erro}</span><div><b>Não consegui baixar</b><small title="${esc(t.erro)}">${esc(t.titulo)}</small></div><button class="x">${IC.x}</button>`, {tempo: 9000});
    }
  }
  if ($("#v-downloads").classList.contains("on")) desenharTarefas();
}
const ROT = {fila: "Na fila", baixando: "Baixando", convertendo: "Finalizando o arquivo", pronto: "Pronto", erro: "Não deu certo", cancelada: "Cancelado"};
function desenharTarefas() {
  const el = $("#tres"), ts = [...S.tarefas].reverse();
  $("#tLimpar").style.visibility = ts.some(t => ["pronto", "erro", "cancelada"].includes(t.estado)) ? "visible" : "hidden";
  if (!ts.length) { el.innerHTML = `<div class="vazio"><div class="eqv">${[55,80,45,100,65,85,50].map((h,k)=>`<i style="height:${h}%;animation-delay:${-k*.17}s"></i>`).join("")}</div><b>Nenhum download ainda</b><span>O que você baixar aparece aqui, com o andamento.</span></div>`; return; }
  const existentes = {}; el.querySelectorAll(".tk").forEach(n => existentes[n.dataset.id] = n);
  if (Object.keys(existentes).length !== ts.length || ts.some(t => !existentes[t.id])) {
    el.innerHTML = ts.map(t => `<div class="tk" data-id="${t.id}">
      <div class="dt">${t.mini ? `<img src="${esc(t.mini)}">` : ""}<span class="tag">${t.formato === "mp3" ? "MP3" : t.formato === "img" ? "IMAGEM" : "MP4"}</span></div>
      <div><b>${esc(t.titulo)}</b><div class="tm" data-r="m"></div><div class="bar"><i></i></div><span data-r="s"></span><div class="err" data-r="e"></div></div>
      <div data-r="a"></div></div>`).join("");
  }
  ts.forEach(t => {
    const n = el.querySelector(`.tk[data-id="${t.id}"]`); if (!n) return;
    n.className = "tk " + t.estado;
    n.querySelector(".bar i").style.width = (t.estado === "erro" ? 100 : t.pct) + "%";
    const extra = t.estado === "baixando" ? [Math.round(t.pct) + "%", t.vel, t.eta && "falta " + t.eta].filter(Boolean).join(" · ") : "";
    n.querySelector('[data-r="m"]').textContent = [t.canal, "→ " + t.destino_nome, extra].filter(Boolean).join("  ·  ");
    const eq = ["baixando", "convertendo"].includes(t.estado) ? '<span class="eqs"><i></i><i></i><i></i></span>' : "";
    n.querySelector('[data-r="s"]').outerHTML = `<span data-r="s" class="st ${t.estado}">${eq}${ROT[t.estado] || t.estado}</span>`;
    n.querySelector('[data-r="e"]').textContent = t.estado === "erro" ? "Detalhe técnico: " + t.erro : "";
    const a = n.querySelector('[data-r="a"]');
    const want = t.estado === "pronto" ? "abrir" : t.estado === "fila" ? "cancelar" : "";
    if (a.dataset.w !== want) {
      a.dataset.w = want;
      a.innerHTML = want === "abrir" ? '<button class="btn sec">Abrir a pasta</button>' : want === "cancelar" ? '<button class="btn sec">Cancelar</button>' : "";
      const bt = a.querySelector("button");
      if (bt && want === "abrir") bt.onclick = () => api("/api/abrir", {path: t.caminho || t.destino, selecionar: !!t.caminho});
      if (bt && want === "cancelar") bt.onclick = async () => { await api("/api/cancelar", {id: t.id}); laçoTarefas(true); };
    }
  });
}
$("#tLimpar").onclick = async () => { await api("/api/limpar", {}); S.tarefas = S.tarefas.filter(t => ["fila", "baixando", "convertendo"].includes(t.estado)); desenharTarefas(); };

/* ---------------- fontes ---------------- */
$("#fBuscar").onclick = () => { const q = $("#fq").value.trim(); if (q.length < 2) { toastErro("Escreva pelo menos 2 letras do nome da fonte."); $("#fq").focus(); return; } carregarFontes(1, "busca", q); };
$("#fq").addEventListener("keydown", e => { if (e.key === "Enter") $("#fBuscar").click(); });
async function iniciarFontes() {
  const r = await api("/api/categorias");
  S.fontes.grupos = r.grupos || [];
  S.fontes.cat = r.atual || "theme.php?cat=405";
  desenharCategorias();
  carregarFontes(1, "cat", "", S.fontes.cat);
}
function grupoDe(cat) { return S.fontes.grupos.find(g => g.url === cat || g.subs.some(x => x.url === cat)); }
function desenharCategorias() {
  const F = S.fontes, busca = F.modo === "busca", g = busca ? null : grupoDe(F.cat);
  $("#fGrupos").innerHTML = F.grupos.map((x, i) => `<button class="chip ${g === x ? "on" : ""}" data-i="${i}" style="animation-delay:${i * 30}ms">${esc(x.nome)}</button>`).join("");
  $("#fGrupos").querySelectorAll(".chip").forEach(b => b.onclick = () => { const x = F.grupos[+b.dataset.i]; carregarFontes(1, "cat", "", x.url || x.subs[0].url); });
  if (!g || (!g.subs.length)) { $("#fSubs").innerHTML = ""; return; }
  const itens = (g.url ? [{nome: "Todas", url: g.url}] : []).concat(g.subs);
  $("#fSubs").innerHTML = itens.map((x, i) => `<button class="sub2 ${x.url === F.cat ? "on" : ""}" data-u="${esc(x.url)}" style="animation-delay:${i * 18}ms">${esc(x.nome)}</button>`).join("");
  $("#fSubs").querySelectorAll(".sub2").forEach(b => b.onclick = () => carregarFontes(1, "cat", "", b.dataset.u));
}
function toastErro(txt) { toast(`<span class="ic err">${IC.erro}</span><div><b>${esc(txt)}</b></div><button class="x">${IC.x}</button>`, {tempo: 6000}); }
async function carregarFontes(p, modo, q, cat) {
  const F = S.fontes; if (modo) { F.modo = modo; F.q = q || ""; } if (cat) F.cat = cat;
  const tok = F.tok = {};
  desenharCategorias();
  const g = grupoDe(F.cat), sub = g && (g.url === F.cat ? "Todas" : (g.subs.find(x => x.url === F.cat) || {}).nome);
  $("#fTit").textContent = F.modo === "busca" ? `Resultados para “${F.q}”` : (g ? g.nome + (sub ? " › " + sub : "") : "Fontes"); $("#fInfo").textContent = "";
  $("#fpag").innerHTML = "";
  $("#fres").innerHTML = Array.from({length: 5}, (_, i) => `<div class="fc" style="animation-delay:${i * 50}ms"><div><div class="skel" style="border:0;padding:0;background:none"><div class="b" style="height:16px;width:200px"></div><div class="b" style="height:11px;width:140px;margin-top:8px"></div></div></div><div></div><div class="fprev load"></div></div>`).join("");
  const r = await api(`/api/fontes?modo=${F.modo}&q=${encodeURIComponent(F.q)}&p=${p}&cat=${encodeURIComponent(F.cat)}`);
  if (F.tok !== tok) return;
  if (r.erro) { $("#fres").innerHTML = '<div class="vazio"><b>Não consegui abrir o site de fontes.</b><span>Verifique a internet e tente de novo.</span></div>'; return; }
  if (!r.fontes.length) { $("#fres").innerHTML = '<div class="vazio"><b>Nenhuma fonte encontrada.</b><span>Tente outro nome — em inglês funciona melhor.</span></div>'; return; }
  F.p = r.pagina; F.total = r.total;
  $("#fInfo").textContent = `Página ${r.pagina} de ${r.total} · ${r.fontes.length} fontes`;
  $("#fres").innerHTML = r.fontes.map((f, i) => `<div class="fc" style="animation-delay:${i * 40}ms" data-i="${i}">
    <div><h3>${esc(f.nome)}</h3><div class="fm">${esc([f.autor && "por " + f.autor, f.downloads && f.downloads + " downloads"].filter(Boolean).join(" · "))}</div>
      ${f.licenca ? `<span class="lic ${f.livre ? "livre" : ""}">${esc(f.licenca)}</span>` : ""}</div>
    <div class="fbtns"></div>
    <div class="fprev ${f.previa ? "load" : ""}">${f.previa ? `<img src="/api/img?t=${T}&u=${encodeURIComponent(f.previa)}" onload="this.classList.add('in');this.parentNode.classList.remove('load')" onerror="this.parentNode.classList.remove('load');this.outerHTML='<span class=sub>(prévia indisponível)</span>'">` : `<span class="alt">${esc(f.nome)}</span>`}</div>
  </div>`).join("");
  r.fontes.forEach((f, i) => botoesFonte($(`#fres .fc[data-i="${i}"] .fbtns`), f));
  paginas($("#fpag"), r.pagina, r.total, n => { carregarFontes(n); $("#main").scrollTo({top: 0}); });
}
function botoesFonte(el, f, ocupado) {
  el.innerHTML = `<button class="btn sec" data-a="site">Ver no site</button>
    <button class="btn sec" data-a="baixar" ${ocupado ? "disabled" : ""}>${ocupado === "baixar" ? '<span class="spin"></span>Baixando' : f.baixada ? "Abrir pasta" : "Baixar"}</button>
    <button class="btn ${f.instalada ? "feito" : "pri"}" data-a="instalar" ${ocupado ? "disabled" : ""}>${ocupado === "instalar" ? '<span class="spin"></span>Instalando' : f.instalada ? "✔ Instalada" : "Instalar"}</button>`;
  el.querySelector('[data-a="site"]').onclick = () => api("/api/site", {url: f.pagina});
  el.querySelector('[data-a="baixar"]').onclick = () => f.baixada ? api("/api/abrir", {path: f.baixada}) : acaoFonte(el, f, "baixar");
  el.querySelector('[data-a="instalar"]').onclick = () => acaoFonte(el, f, "instalar");
}
async function acaoFonte(el, f, acao) {
  botoesFonte(el, f, acao);
  const r = await api("/api/fonte", {slug: f.slug, nome: f.nome, acao});
  if (r.erro) { botoesFonte(el, f); toastErro(`Não consegui pegar a fonte ${f.nome}. Verifique a internet.`); return; }
  if (acao === "baixar") { f.baixada = r.resultado; toast(`<span class="ic">${IC.ok}</span><div><b>Fonte ${esc(f.nome)} salva</b><small>Em Downloads › Fontes</small><div class="tb"><button class="btn sec" data-a="abrir">Abrir a pasta</button></div></div><button class="x">${IC.x}</button>`, {tempo: 8000}).querySelector('[data-a="abrir"]').onclick = () => api("/api/abrir", {path: f.baixada}); }
  else { f.instalada = true; ding(); toast(`<span class="ic">${IC.ok}</span><div><b>Fonte ${esc(f.nome)} instalada!</b><small>Já aparece no Word, no Paint e nos outros programas.</small></div><button class="x">${IC.x}</button>`, {tempo: 8000}); }
  botoesFonte(el, f);
}


/* ---------------- imagens ---------------- */
const IM = {busca: "", p: 1, res: [], fim: false, feitas: {}, tok: null, lb: -1, maxPag: 1};
function imgVazio() {
  $("#ires").innerHTML = `<div class="vazio"><div class="eqv">${[55,80,45,100,65,85,50].map((h,k)=>`<i style="height:${h}%;animation-delay:${-k*.17}s"></i>`).join("")}</div><b>As imagens vão aparecer aqui</b><span>Dica: escreva o que você quer ver, do jeito que falaria.</span></div>`;
  $("#iTit").textContent = "Resultados"; $("#iInfo").textContent = ""; $("#ipag").innerHTML = ""; $("#iFonte").textContent = "";
}
$("#iBuscar").onclick = () => { const q = $("#iq").value.trim(); if (!q) { toastErro("Escreva o que você quer procurar."); $("#iq").focus(); return; } IM.busca = q; IM.maxPag = 1; carregarImagens(1); };
$("#iq").addEventListener("keydown", e => { if (e.key === "Enter") $("#iBuscar").click(); });
async function carregarImagens(p) {
  const tok = IM.tok = {};
  const bt = $("#iBuscar"); bt.disabled = true; bt.innerHTML = '<span class="spin"></span>Pesquisando';
  $("#iTit").textContent = `Imagens de “${IM.busca}”`; $("#iInfo").textContent = ""; $("#ipag").innerHTML = "";
  $("#ires").innerHTML = '<div class="mason">' + Array.from({length: 15}, (_, i) => `<div class="im" style="animation-delay:${i * 30}ms"><span class="ph" style="height:${140 + (i * 67) % 160}px"></span></div>`).join("") + "</div>";
  let r; try { r = await api(`/api/imagens?q=${encodeURIComponent(IM.busca)}&p=${p}`); } catch (e) { r = {erro: String(e)}; }
  bt.disabled = false; bt.textContent = "Pesquisar";
  if (IM.tok !== tok) return;
  if (r.erro || !r.res) { $("#ires").innerHTML = '<div class="vazio"><b>Não consegui pesquisar agora.</b><span>Verifique a internet e tente de novo.</span></div>'; return; }
  if (!r.res.length) {
    if (p > 1) { toastErro("Não há mais imagens. Esta foi a última página."); IM.fim = true; IM.maxPag = p - 1; paginasImg(); return; }
    $("#ires").innerHTML = '<div class="vazio"><b>Nenhuma imagem encontrada.</b><span>Tente escrever de outro jeito.</span></div>'; return;
  }
  IM.p = p; IM.res = r.res; IM.fim = r.fim; IM.maxPag = Math.max(IM.maxPag, p);
  $("#iInfo").textContent = `Página ${p} · ${r.res.length} imagens`;
  $("#iFonte").textContent = (r.fonte === "openverse" ? "Imagens do Openverse" : r.fonte === "bing" ? "Imagens encontradas pelo Bing Imagens" : "Modo de demonstração") +
    " · cada imagem pertence ao seu site de origem; confira antes de usar em trabalhos que vão ser vendidos.";
  $("#ires").innerHTML = '<div class="mason">' + r.res.map((it, i) => {
    const prop = it.larg && it.alt ? it.alt / it.larg : 0.62 + ((i * 37) % 60) / 100;
    return `<div class="im ${IM.feitas[it.url] ? "feita" : ""}" data-i="${i}" style="animation-delay:${Math.min(i, 20) * 25}ms">
      <span class="ph" style="aspect-ratio:1/${prop.toFixed(3)}"></span>
      <div class="ov2"><div><b title="${esc(it.titulo)}">${esc(it.titulo || IM.busca)}</b><small>${esc(it.site)}</small></div>${botaoImg(it)}</div></div>`;
  }).join("") + "</div>";
  document.querySelectorAll("#ires .im").forEach(c => {
    const it = IM.res[+c.dataset.i], ph = c.querySelector(".ph");
    const img = new Image(); img.decoding = "async"; img.referrerPolicy = "no-referrer"; img.alt = "";
    img.onload = () => { ph.replaceWith(img); requestAnimationFrame(() => img.classList.add("in")); };
    img.onerror = () => c.remove();
    img.src = it.mini;
    c.onclick = e => { const b = e.target.closest(".bimg"); if (b) { e.stopPropagation(); baixarImagem(+c.dataset.i); return; } abrirLB(+c.dataset.i); };
  });
  paginasImg();
}
function paginasImg() {
  paginas($("#ipag"), IM.p, IM.fim ? IM.maxPag : IM.maxPag + 1, n => { carregarImagens(n); $("#main").scrollTo({top: 0}); });
}
function botaoImg(it, grande) {
  const st = IM.feitas[it.url];
  if (st === "baixando") return `<button class="bimg" disabled><span class="spin"></span>Baixando</button>`;
  if (st) return `<button class="bimg ok">${IC.ok}Baixada</button>`;
  return `<button class="bimg">${IC.baixar}${grande ? "Baixar imagem" : "Baixar"}</button>`;
}
function atualizarBotoesImg(i) {
  const it = IM.res[i]; if (!it) return;
  const c = $(`#ires .im[data-i="${i}"]`);
  if (c) { c.querySelector(".bimg").outerHTML = botaoImg(it); c.classList.toggle("feita", !!IM.feitas[it.url] && IM.feitas[it.url] !== "baixando"); }
  if (IM.lb === i) { const b = $("#lbBtn"); if (b) { b.outerHTML = botaoImg(it, true).replace("<button", '<button id="lbBtn"'); $("#lbBtn").onclick = () => baixarImagem(i); } }
}
async function baixarImagem(i) {
  const it = IM.res[i]; if (!it || IM.feitas[it.url]) return;
  IM.feitas[it.url] = "baixando"; atualizarBotoesImg(i);
  const r = await api("/api/imagem", {url: it.url, mini: it.mini, titulo: it.titulo || IM.busca, pagina: it.pagina, site: it.site, q: IM.busca});
  if (r.erro) { delete IM.feitas[it.url]; atualizarBotoesImg(i); toastErro("Não consegui baixar essa imagem. Tente outra."); return; }
  IM.feitas[it.url] = "ok"; atualizarBotoesImg(i); ding();
  const t = r.tarefa; S.tarefas.push(t); S.vistas[t.id] = "pronto";
  const tt = toast(`<span class="ic">${IC.ok}</span><div><b>Imagem baixada!</b><small>${esc(t.arquivo)} · ${esc(t.destino_nome)}${t.menor ? " (versão menor: o site não liberou a grande)" : ""}</small>
    <div class="tb"><button class="btn sec" data-a="abrir">Mostrar na pasta</button></div></div><button class="x">${IC.x}</button>`, {tempo: 7000});
  tt.querySelector('[data-a="abrir"]').onclick = () => { api("/api/abrir", {path: t.caminho, selecionar: true}); fecharToast(tt); };
}
function abrirLB(i) {
  IM.lb = i; const it = IM.res[i]; if (!it) return;
  pararPrevia();
  let el = $("#lb");
  if (!el) { el = document.createElement("div"); el.id = "lb"; el.className = "lbx"; document.body.appendChild(el); }
  el.innerHTML = `<div class="area"><img id="lbImg" src="${esc(it.mini)}" referrerpolicy="no-referrer">
      <button class="nav2 e" id="lbE" ${i <= 0 ? "hidden" : ""}><svg class="i" viewBox="0 0 24 24"><path d="M15 18l-6-6 6-6"/></svg></button>
      <button class="nav2 d" id="lbD" ${i >= IM.res.length - 1 ? "hidden" : ""}><svg class="i" viewBox="0 0 24 24"><path d="M9 18l6-6-6-6"/></svg></button>
      <button class="fx" id="lbX">${IC.x}</button></div>
    <div class="bar2"><div><b>${esc(it.titulo || IM.busca)}</b><small>${esc(it.site)} · ${i + 1} de ${IM.res.length}</small></div>
      ${it.pagina ? '<button class="btn sec" id="lbSite">Ver no site</button>' : ""}${botaoImg(it, true).replace("<button", '<button id="lbBtn"')}</div>`;
  const grande = new Image(); grande.referrerPolicy = "no-referrer";
  grande.onload = () => { if (IM.lb === i && $("#lbImg")) $("#lbImg").src = it.url; };
  grande.src = it.url;
  $("#lbX").onclick = fecharLB; $("#lbE").onclick = () => abrirLB(i - 1); $("#lbD").onclick = () => abrirLB(i + 1);
  $("#lbBtn").onclick = () => baixarImagem(i);
  if ($("#lbSite")) $("#lbSite").onclick = () => api("/api/site", {url: it.pagina});
  el.querySelector(".area").onclick = e => { if (e.target.classList.contains("area")) fecharLB(); };
}
function fecharLB() { IM.lb = -1; const el = $("#lb"); if (el) el.remove(); }
document.addEventListener("keydown", e => {
  if (IM.lb < 0) return;
  if (e.key === "Escape") fecharLB();
  else if (e.key === "ArrowLeft" && IM.lb > 0) abrirLB(IM.lb - 1);
  else if (e.key === "ArrowRight" && IM.lb < IM.res.length - 1) abrirLB(IM.lb + 1);
});

/* ---------------- teclado e fechamento ---------------- */
document.addEventListener("keydown", e => {
  if (e.key === "Escape" && S.modal && !S.modal.obrigatorio) fecharSeletor();
  else if (e.key === "Enter" && S.modal) confirmarSeletor();
});
window.addEventListener("pagehide", () => { try { navigator.sendBeacon("/api/fechar?t=" + T, "{}"); } catch (e) {} });
document.addEventListener("visibilitychange", () => { if (!document.hidden) api("/api/ping"); });

mudarModo("nome", false); vazio("Os resultados da busca vão aparecer aqui.");
guia("Escolha para onde vão os arquivos baixados.");
requestAnimationFrame(() => { moverInd($("#segModo")); moverInd($("#fmt")); });
abertura();
</script>
</body>
</html>
"""

if __name__ == "__main__":
    principal()
