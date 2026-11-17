# Baixador: guia do projeto

## O que tem aqui

| Arquivo | Para que serve |
|---|---|
| `Baixador.bat` | O programa inteiro. A primeira parte é um lote do Windows que acha (ou instala) o Python; o resto é Python (servidor local, yt-dlp, fontes, imagens) com a tela em HTML/CSS/JS. |
| `baixador.ico` | Ícone do aplicativo, com um desenho próprio para cada tamanho (16 a 256 px). |
| `ferramentas/preparar.py` | Transforma o `.bat` em `build/Baixador.py` para gerar o `.exe`, já com o número da versão da Release. |
| `.github/workflows/publicar.yml` | Gera o `Baixador.exe` no GitHub, testa e anexa na Release. |
| `docs/` | Site de download (GitHub Pages): https://limabat.github.io/Baixador/ |

## Rodar no próprio computador

Dois cliques no `Baixador.bat`. Na primeira vez ele instala o que falta (yt-dlp, Pillow, pywebview e o ffmpeg).

Para testar só a tela, sem internet: `python -x Baixador.bat --demo --nova`.

Os dados ficam em `%LOCALAPPDATA%\Baixador` (configuração, registro de erros em `baixador_log.txt`, ffmpeg).

## Publicar uma versão nova

1. Envie as mudanças do `Baixador.bat` para o GitHub.
2. Em **Releases > Draft a new release**, crie uma tag **maior que a anterior** (v3.2, v3.3...), escreva o que mudou e clique em **Publish release**.
3. Em uns 10 minutos o `Baixador.exe` aparece anexado na release (acompanhe na aba **Actions**).

Quem já tem o Baixador recebe o aviso "Nova versão disponível" em até 3 horas e atualiza com um clique. O componente de busca do YouTube (yt-dlp) se atualiza sozinho a cada 2 dias, sem precisar de versão nova.

Para só gerar o `.exe` sem publicar: aba **Actions > Publicar versão > Run workflow** (o arquivo fica em *Artifacts*).
