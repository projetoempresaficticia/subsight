#!/usr/bin/env python3
"""Prepara a marca e o fundo do Subsight a partir dos originais.

Ao contrário do Prepacoin, aqui a marca NÃO pode ser uma máscara: tem o
visto a branco dentro do círculo laranja, e uma máscara de um canal só
perdia essa segunda cor. Vai como PNG com transparência.

O fundo vem de um PNG de 847 KB, que é peso a mais para uma imagem
decorativa. Sai em WebP, que num desenho geométrico de arestas duras
poupa muito sem se notar.

O recorte é pelo LARANJA, não pela transparência. O ficheiro traz um
arco cinzento fantasma em baixo que ocupa 35% da altura e, a 46px, não
se vê: recortar por ele encolhia o traço da assinatura para 2px e a
marca lia-se como uma mancha. Pelo laranja, o gesto ocupa a caixa toda.

Produz:
  web/marca/subsight-marca.png    a assinatura, deitada (~1,73:1), para
                                  o cabeçalho
  web/marca/subsight-512.png      a mesma, quadrada, para o separador e
                                  para partilha
  web/marca/subsight-fundo.webp   o fundo da entrada
  apple-touch-icon.png            180x180 sobre branco (o iOS não aceita
                                  transparência: punha-a sobre preto)
  favicon-32.png / favicon.ico
"""

import pathlib
from PIL import Image

RAIZ = pathlib.Path(__file__).resolve().parent.parent
ICONE = pathlib.Path(r"C:/Users/devel/Downloads/icone.png")
FUNDO = pathlib.Path(r"C:/Users/devel/Downloads/ChatGPT Image 4 de set. de 2026, 20_21_26.png")


def quadrado(caixa):
    """Alarga a caixa para ficar quadrada. Preenche, nunca estica."""
    x0, y0, x1, y1 = caixa
    lado = max(x1 - x0, y1 - y0)
    cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
    meio = lado // 2
    return (cx - meio, cy - meio, cx - meio + lado, cy - meio + lado)


def main():
    for f in (ICONE, FUNDO):
        if not f.is_file():
            raise SystemExit(f'não encontro o original: {f}')

    destino = RAIZ / 'web' / 'marca'
    destino.mkdir(parents=True, exist_ok=True)

    # ── a marca ──────────────────────────────────────────────────────
    im = Image.open(ICONE).convert('RGBA')
    r, g, b, a = im.split()
    zero = Image.new('L', im.size, 0)

    def M(canal, teste):
        return Image.eval(canal, lambda v: 255 if teste(v) else 0)

    # o laranja: vermelho alto, azul baixo, opaco
    laranja = Image.composite(M(b, lambda v: v < 140), zero, M(r, lambda v: v > 180))
    laranja = Image.composite(laranja, zero, M(a, lambda v: v > 150))

    x0, y0, x1, y1 = laranja.getbbox()
    folga = int((x1 - x0) * 0.03)          # um respiro, para não cortar o traço
    caixa = (x0 - folga, y0 - folga, x1 + folga, y1 + folga)
    print('marca recortada pelo laranja:', caixa,
          '->', caixa[2] - caixa[0], 'x', caixa[3] - caixa[1])

    # A marca aparece no cabeçalho a 63x38. Guardar os 891px do recorte
    # eram 240 KB para desenhar 63 — reduz-se a 400px de largura, que
    # ainda chega para ecrãs de densidade dupla e tripla, e sai em WebP.
    deitada = im.crop(caixa)
    largura = 400
    altura = round(deitada.height * largura / deitada.width)
    deitada = deitada.resize((largura, altura), Image.LANCZOS)

    alvo = destino / 'subsight-marca.webp'
    deitada.save(alvo, 'WEBP', quality=92, method=6)
    print(f'escrito web/marca/subsight-marca.webp {deitada.size} '
          f'{alvo.stat().st_size/1024:.0f} KB')

    reserva = destino / 'subsight-marca.png'
    deitada.save(reserva, optimize=True)
    print(f'escrito web/marca/subsight-marca.png  {deitada.size} '
          f'{reserva.stat().st_size/1024:.0f} KB')

    # a versão quadrada centra a mesma marca, sem a esticar
    marca = im.crop(quadrado(caixa))

    def redimensionar(lado):
        return marca.resize((lado, lado), Image.LANCZOS)

    redimensionar(512).save(destino / 'subsight-512.png', optimize=True)
    print('escrito web/marca/subsight-512.png')

    # O iOS não respeita transparência no ícone do ecrã inicial: o que
    # fosse transparente saía preto. Compõe-se sobre branco, e com uma
    # margem, porque o sistema já arredonda e corta as bordas.
    def sobre_branco(lado, margem=0.12):
        base = Image.new('RGBA', (lado, lado), (255, 255, 255, 255))
        interior = int(lado * (1 - 2 * margem))
        m = marca.resize((interior, interior), Image.LANCZOS)
        pos = (lado - interior) // 2
        base.alpha_composite(m, (pos, pos))
        return base.convert('RGB')

    sobre_branco(180).save(RAIZ / 'apple-touch-icon.png', optimize=True)
    print('escrito apple-touch-icon.png')

    # No separador do browser a marca é minúscula: sem margem, para
    # aproveitar cada pixel.
    redimensionar(32).save(RAIZ / 'favicon-32.png', optimize=True)
    print('escrito favicon-32.png')
    redimensionar(256).save(RAIZ / 'favicon.ico',
                            sizes=[(16, 16), (32, 32), (48, 48), (64, 64)])
    print('escrito favicon.ico')

    # ── o fundo ──────────────────────────────────────────────────────
    fundo = Image.open(FUNDO).convert('RGB')
    print('fundo original', fundo.size, f'{FUNDO.stat().st_size/1024:.0f} KB')

    alvo = destino / 'subsight-fundo.webp'
    fundo.save(alvo, 'WEBP', quality=88, method=6)
    print(f'escrito web/marca/subsight-fundo.webp  {alvo.stat().st_size/1024:.0f} KB')

    # reserva para quem não suportar WebP (raro, mas o ficheiro é pequeno)
    reserva = destino / 'subsight-fundo.jpg'
    fundo.save(reserva, 'JPEG', quality=86, optimize=True, progressive=True)
    print(f'escrito web/marca/subsight-fundo.jpg   {reserva.stat().st_size/1024:.0f} KB')


if __name__ == '__main__':
    main()
