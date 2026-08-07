// A canvas that draws nothing and remembers everything.
//
// The field is the hardest part of the port to argue about: dozens of
// numbers per dot, all of them the product of a lens, a decay, a colour
// ripple and a breath. Comparing screenshots would only ever tell us the
// two look similar. So instead of rasterising, this stands in for the 2D
// context and records the primitives the web app asks for — position,
// radius, colour, alpha — and the Swift renderer is checked against that
// list, primitive for primitive.
//
// Only the calls src/grid.ts actually makes are implemented. Anything else
// would be a silent hole in the comparison, so it throws.

const RGBA = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/;

function parseColor(css) {
    const match = RGBA.exec(String(css));
    if (!match) throw new Error(`unexpected colour: ${css}`);
    return {
        r: Number(match[1]),
        g: Number(match[2]),
        b: Number(match[3]),
        a: match[4] === undefined ? 1 : Number(match[4]),
    };
}

/// The offscreen canvas `glowSprite` builds its halo on. Nothing is drawn;
/// the sprite is identified by the colour its gradient starts from, which is
/// what the recorder needs in order to say which halo was used.
function spriteCanvas() {
    const canvas = { width: 0, height: 0, color: null };
    canvas.getContext = () => ({
        fillStyle: null,
        fillRect() {},
        createRadialGradient() {
            return {
                addColorStop(stop, css) {
                    if (stop === 0) canvas.color = parseColor(css);
                },
            };
        },
    });
    return canvas;
}

export function installDocumentStub() {
    if (globalThis.document) return;
    globalThis.document = {
        createElement(tag) {
            if (tag !== 'canvas') throw new Error(`unexpected element: ${tag}`);
            return spriteCanvas();
        },
    };
}

/// Records every primitive the field asks for, in order.
export function makeRecorder() {
    const ops = [];

    let path = null;
    let gradient = null;

    const ctx = {
        globalAlpha: 1,
        globalCompositeOperation: 'source-over',
        fillStyle: '',
        strokeStyle: '',
        lineWidth: 1,
        lineCap: 'butt',

        beginPath() {
            path = { arc: null, from: null, to: null };
        },
        arc(x, y, radius) {
            path.arc = { x, y, radius };
        },
        fill() {
            const colour = parseColor(ctx.fillStyle);
            ops.push({
                op: 'dot',
                x: path.arc.x,
                y: path.arc.y,
                radius: path.arc.radius,
                r: colour.r,
                g: colour.g,
                b: colour.b,
                alpha: colour.a,
            });
        },
        moveTo(x, y) {
            path.from = { x, y };
        },
        lineTo(x, y) {
            path.to = { x, y };
        },
        createLinearGradient() {
            gradient = { stops: [] };
            return {
                addColorStop(stop, css) {
                    gradient.stops.push({ stop, colour: parseColor(css) });
                },
            };
        },
        stroke() {
            // The streak fades from its colour to nothing, so stop 0 is what
            // carries both the colour and the strength.
            const head = gradient.stops.find((s) => s.stop === 0).colour;
            ops.push({
                op: 'streak',
                x0: path.from.x,
                y0: path.from.y,
                x1: path.to.x,
                y1: path.to.y,
                width: ctx.lineWidth,
                r: head.r,
                g: head.g,
                b: head.b,
                alpha: head.a,
            });
        },
        drawImage(sprite, x, y, width, height) {
            ops.push({
                op: 'glow',
                x,
                y,
                width,
                height,
                r: sprite.color.r,
                g: sprite.color.g,
                b: sprite.color.b,
                alpha: ctx.globalAlpha,
            });
        },
        clearRect() {},
        strokeRect() {},
        setTransform() {},
    };

    return { ctx, ops, reset: () => ops.splice(0, ops.length) };
}
