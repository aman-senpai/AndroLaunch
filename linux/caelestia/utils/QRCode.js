.pragma library

// Standard QR Code Matrix Generator (Model 2, Byte Mode, EC Level L)
// Generates standard 2D Boolean matrices for arbitrary text strings.

const GF = new Uint8Array(256);
const LOG = new Uint8Array(256);
let x = 1;
for (let i = 0; i < 255; i++) {
    GF[i] = x;
    LOG[x] = i;
    x = (x << 1) ^ (x >= 128 ? 0x11d : 0);
}
GF[255] = GF[0];

function gmul(a, b) {
    return (a === 0 || b === 0) ? 0 : GF[(LOG[a] + LOG[b]) % 255];
}

function rsPoly(n) {
    let p = [1];
    for (let i = 0; i < n; i++) {
        let next = new Array(p.length + 1).fill(0);
        for (let j = 0; j < p.length; j++) {
            next[j] ^= gmul(p[j], GF[i]);
            next[j + 1] ^= p[j];
        }
        p = next;
    }
    return p;
}

function rsCompute(data, ecCount) {
    const poly = rsPoly(ecCount);
    const out = new Array(data.length + ecCount).fill(0);
    for (let i = 0; i < data.length; i++) out[i] = data[i];
    for (let i = 0; i < data.length; i++) {
        const factor = out[i];
        if (factor !== 0) {
            for (let j = 0; j < poly.length; j++) {
                out[i + j] ^= gmul(poly[j], factor);
            }
        }
    }
    return out.slice(data.length);
}

const PAD = [0xec, 0x11];
const SPECS = [
    [1, 21, 19, 7, 1],
    [2, 25, 34, 10, 1],
    [3, 29, 55, 15, 1],
    [4, 33, 80, 20, 1],
    [5, 37, 108, 26, 1],
    [6, 41, 136, 18, 2]
];

function generate(text) {
    const utf8 = [];
    for (let i = 0; i < text.length; i++) {
        let code = text.charCodeAt(i);
        if (code < 128) {
            utf8.push(code);
        } else if (code < 2048) {
            utf8.push(192 | (code >> 6), 128 | (code & 63));
        } else {
            utf8.push(224 | (code >> 12), 128 | ((code >> 6) & 63), 128 | (code & 63));
        }
    }

    let spec = SPECS.find(s => s[2] - 3 >= utf8.length);
    if (!spec) spec = SPECS[SPECS.length - 1];

    const [ver, size, dataCap, ecCount, blocks] = spec;

    let bits = [];
    function pushBits(val, len) {
        for (let i = len - 1; i >= 0; i--) bits.push((val >> i) & 1);
    }

    pushBits(0b0100, 4); // Byte Mode
    pushBits(utf8.length, 8);
    for (let b of utf8) pushBits(b, 8);
    pushBits(0, Math.min(4, dataCap * 8 - bits.length));
    while (bits.length % 8 !== 0) bits.push(0);

    const bytes = [];
    for (let i = 0; i < bits.length; i += 8) {
        let byte = 0;
        for (let j = 0; j < 8; j++) byte = (byte << 1) | bits[i + j];
        bytes.push(byte);
    }
    let padIdx = 0;
    while (bytes.length < dataCap) {
        bytes.push(PAD[padIdx % 2]);
        padIdx++;
    }

    const blockSize = Math.floor(dataCap / blocks);
    const dataBlocks = [];
    const ecBlocks = [];
    for (let b = 0; b < blocks; b++) {
        const start = b * blockSize;
        const end = (b === blocks - 1) ? dataCap : (b + 1) * blockSize;
        const slice = bytes.slice(start, end);
        dataBlocks.push(slice);
        ecBlocks.push(rsCompute(slice, ecCount));
    }

    const finalStream = [];
    const maxDataLen = Math.max(...dataBlocks.map(b => b.length));
    for (let i = 0; i < maxDataLen; i++) {
        for (let b = 0; b < blocks; b++) {
            if (i < dataBlocks[b].length) finalStream.push(dataBlocks[b][i]);
        }
    }
    for (let i = 0; i < ecCount; i++) {
        for (let b = 0; b < blocks; b++) {
            finalStream.push(ecBlocks[b][i]);
        }
    }

    const matrix = Array.from({ length: size }, () => new Array(size).fill(null));
    const isReserved = Array.from({ length: size }, () => new Array(size).fill(false));

    function setFinder(r, c) {
        for (let y = -1; y <= 7; y++) {
            for (let x = -1; x <= 7; x++) {
                const row = r + y, col = c + x;
                if (row >= 0 && row < size && col >= 0 && col < size) {
                    isReserved[row][col] = true;
                    if (y >= 0 && y <= 6 && x >= 0 && x <= 6) {
                        matrix[row][col] = (y === 0 || y === 6 || x === 0 || x === 6 || (y >= 2 && y <= 4 && x >= 2 && x <= 4)) ? 1 : 0;
                    } else {
                        matrix[row][col] = 0;
                    }
                }
            }
        }
    }

    setFinder(0, 0);
    setFinder(0, size - 7);
    setFinder(size - 7, 0);

    if (ver >= 2) {
        const alignPos = [6, size - 7];
        for (let r of alignPos) {
            for (let c of alignPos) {
                if (isReserved[r][c]) continue;
                for (let y = -2; y <= 2; y++) {
                    for (let x = -2; x <= 2; x++) {
                        isReserved[r + y][c + x] = true;
                        matrix[r + y][c + x] = (Math.max(Math.abs(x), Math.abs(y)) !== 1) ? 1 : 0;
                    }
                }
            }
        }
    }

    for (let i = 8; i < size - 8; i++) {
        if (!isReserved[6][i]) {
            isReserved[6][i] = true;
            matrix[6][i] = (i % 2 === 0) ? 1 : 0;
        }
        if (!isReserved[i][6]) {
            isReserved[i][6] = true;
            matrix[i][6] = (i % 2 === 0) ? 1 : 0;
        }
    }

    isReserved[4 * ver + 9][8] = true;
    matrix[4 * ver + 9][8] = 1;

    for (let i = 0; i < 9; i++) {
        if (i < size) { isReserved[8][i] = true; isReserved[i][8] = true; }
    }
    for (let i = size - 8; i < size; i++) {
        isReserved[8][i] = true;
        isReserved[i][8] = true;
    }

    let bitIdx = 0;
    const totalBits = finalStream.length * 8;
    let right = size - 1;
    let up = true;
    while (right > 0) {
        if (right === 6) right--;
        for (let vert = 0; vert < size; vert++) {
            const y = up ? (size - 1 - vert) : vert;
            for (let x = right; x >= right - 1; x--) {
                if (!isReserved[y][x]) {
                    let bit = 0;
                    if (bitIdx < totalBits) {
                        const byte = finalStream[Math.floor(bitIdx / 8)];
                        bit = (byte >> (7 - (bitIdx % 8))) & 1;
                        bitIdx++;
                    }
                    matrix[y][x] = ((y + x) % 2 === 0) ? (bit ^ 1) : bit;
                }
            }
        }
        up = !up;
        right -= 2;
    }

    const formatBits = [1, 1, 1, 0, 1, 1, 1, 1, 1, 0, 0, 0, 1, 0, 0];
    for (let i = 0; i < 6; i++) matrix[8][i] = formatBits[i];
    matrix[8][7] = formatBits[6];
    matrix[8][8] = formatBits[7];
    matrix[7][8] = formatBits[8];
    for (let i = 0; i < 6; i++) matrix[5 - i][8] = formatBits[9 + i];

    for (let i = 0; i < 8; i++) matrix[size - 1 - i][8] = formatBits[i];
    for (let i = 7; i > 0; i--) matrix[8][size - i] = formatBits[15 - i];

    return { size, matrix };
}
