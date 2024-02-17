const PNG = require('pngjs/browser').PNG;

const fs = require('fs');
const path = require('path');
const yargs = require('yargs/yargs')
const { hideBin } = require('yargs/helpers')

const argv = yargs(hideBin(process.argv))
        .option('workdir', {
            alias: 'w',
            description: 'The path to the assets - eg: ./maps',
            type: 'string',
        })
        .option('input', {
            alias: 'i',
            description: 'The path to the PNG file - eg: ./maps/mymap.ldtk',
            type: 'string',
        })
        .option('output', {
            alias: 'o',
            description: 'Folder to output files to - eg: ./output',
            type: 'string',
        })                
        .option('fcm', {
            alias: 'f',
            description: 'use input png file is for FCM',
            type: 'boolean',
        })     
        .option('ncm', {
            alias: 'n',
            description: 'the input png file is for NCM',
            type: 'boolean',
        })                   
        .option('chroffs', {
            alias: 'c',
            description: 'offset to be applied to the character values',
            type: 'number',
        })                   
        .help()
        .alias('help', 'h')
        .argv;


if(!argv.ncm && !argv.fcm) {
    throw new Error("You must provide a char mode, --ncm or --fcm")
}


let ldtk = fetchLDTKFile(argv.workdir, argv.input)

let tilesets = fetchTilesets(argv.workdir, ldtk)
let levels = fetchLevels(ldtk)

let outputPath = setOutputPath(argv.output)

saveTilesets(tilesets)
saveLevels(levels, tilesets)


function fetchLDTKFile(assetPath, filename) {
    // return the parsed JSON tree
    //
    let ldtkpath = path.resolve(assetPath, filename)
    var data = fs.readFileSync(ldtkpath);
    try {
        return JSON.parse(data)
    } catch(e) {
        throw new Error("Could not parse the LDTK file "+ldtkpath+" Is this an LDTK file????")
    }
}

function setOutputPath(pathName) {
    let outputPath = pathName || "./"
    if (!fs.existsSync(outputPath)) {
        fs.mkdirSync(outputPath);
    }
    return outputPath;
}

function fetchTilesets(assetPath, ldtk) {
    // return a list of tilesets
    //
    let tilesets = []

    console.log("*-----------------------------------")
    console.log("parsing tilesets")

    //
    let inputName = path.parse(argv.input).name

    let tilesetCount = ldtk.defs.tilesets.length
    console.log("tilesetCount = " + tilesetCount)
    for(var ts=0; ts<tilesetCount; ts++) {
        let tileset = ldtk.defs.tilesets[ts]

        let tilesetpath = path.resolve(assetPath, tileset.relPath)
        console.log("tileset[" + ts + "] name = " + tilesetpath)

        let png = getPngData(tilesetpath)

        let paletteData = getPaletteData(png)

        console.log("tileset dims " + png.width + " x " + png.height)

        let chars = null
        if(argv.fcm) {
            chars = getFCMData(png, paletteData.palette)
        }

        if(argv.ncm) {
            chars = getNCMData(png, paletteData.palette, 16, 8)
        }

        let tiles = fetchTiles(ldtk, tileset, chars.remap)

        let newTileset = {
            name : tileset.identifier,
            uid : tileset.uid,
            chrs: chars, 
            pal: paletteData.pal,
            tiles: tiles
        }

        tilesets.push(newTileset)
    }

    return tilesets
}

// Parses and dedups a list of tiles, these are NxN character indexes
//
function fetchTiles(ldtk, tileset, chrRemap) {
    // 
    let uniques = []
    let remap = []

    // create tile definitions
    let wid = tileset.pxWid
    let hei = tileset.pxHei
    let size = tileset.tileGridSize

    let rowsize = wid / size
    let charsPerRow = wid / (argv.ncm ? 16 : 8)
    let tileCount = (wid/size) * (hei/size) 

    for(var t=0; t<tileCount; t++) {
        let base = Math.floor(t / rowsize) * (wid/16) * (size/8) + (t%rowsize) * (size/16)
        
        let tile = []
        for(var y=0; y<size /8; y++) {
            for(var x=0; x< size/(argv.ncm ? 16 : 8); x++) {
                let tindx = base + x + (y * charsPerRow)

                tile.push(chrRemap[tindx])
            }
        }

        let tileStr = JSON.stringify(tile)

        let uniqueIndex = uniques.findIndex(a => {
            return (
                tileStr === a.tstr
            );
        })

        uniqueIndex = -1

        if (uniqueIndex == -1) {
            let uniqueTile = {
                tstr: tileStr,
                data: tile
            }

            uniqueIndex = uniques.length

            uniques.push(uniqueTile)

            // console.log(uniqueIndex)
            // console.log(t, tile.map( a=> "$"+a.toString(16).padStart(4,'0')))
        }

        remap[t] = uniqueIndex
    }

    return { uniques, remap }
}

function getPngData(pngName) {
    var data = fs.readFileSync(path.resolve(pngName));
    return PNG.sync.read(data);
}

function nswap(a) {
    return (((a & 0xf) << 4) | ((a >> 4) & 0xf))
}

function getPaletteData(png) {
    let palette = [];
    for (var c = 0; c < png.palette.length; c++) 
    {
        let color = png.palette[c]
        let pal = {
            red: color[0],
            green: color[1],
            blue: color[2],
            alpha: color[3]
        };
        palette.push(pal);
    }
    console.log("Palette size: " + palette.length + " colors");
    console.log(palette)

    let maxPaletteEntries = (argv.ncm ? 16 : 256)

    if(palette.length > maxPaletteEntries)  throw(new Error(`Your input image has too many palette entries (${palette.length})`))

    let pal = { r: [], g: [], b: [] }
    for(var i = 0;i < maxPaletteEntries; i++) 
    {
        if (i < palette.length) 
        {
            let color = palette[i]
            pal.r.push(nswap(color.red))
            pal.g.push(nswap(color.green))
            pal.b.push(nswap(color.blue))
        } 
        else 
        {
            pal.r.push(0)
            pal.g.push(0)
            pal.b.push(0)
        }
    }

    console.log("Padded palette size: " + pal.r.length + " colors");

    return {palette, pal}
}

function getFCMData(png, palette) {
    let data = []
    let highestCol = -1
    for(var y=0; y<png.height; y+=8) {
        for(var x=0; x<png.width; x+=8) {
            for(var r=0; r<8; r++) {
                for(var c=0; c<8; c++) {
                    let i = ((y + r) * (png.width * 4) + ((x + c) * 4))
                    //find the color
                    let col = palette.findIndex(a => {
                        return (
                            png.data[i+0] === a.red &&
                            png.data[i+1] === a.green &&
                            png.data[i+2] === a.blue &&
                            png.data[i+3] === a.alpha
                        );
                    })
                    data.push(col)
                    if(col > highestCol) highestCol = col
                }
            }
        }
    }

    return { data }
}

function getNCMData(png, palette, cwid, chei) {
    //
    let uniques = []
    let remap = []

    //
    let charsW = (png.width/cwid)
    let charsH = (png.height/chei)

    console.log("scanning " + charsW + " x " + charsH)

    // scan through all of the chars
    //
    for(var y = 0; y < charsH; y++) {
        for(var x = 0; x < charsW; x++) {

            let charCols = []
            let charIndx = (y * charsW) + x

            // scan each char
            //
            for(var r = 0; r < chei; r++) {
                for(var c = 0; c < cwid; c+=2) {
                    // figure out the texel index
                    //
                    let i = ((((y * chei) + r) * png.width) + ((x * cwid) + c)) * 4
                    let j = i + 4

                    // find the color
                    let col1 = palette.findIndex(a => {
                        return (
                            png.data[i+0] === a.red &&
                            png.data[i+1] === a.green &&
                            png.data[i+2] === a.blue &&
                            png.data[i+3] === a.alpha
                        );
                    })

                    //originalPalIndex.push(col1)
                    //if(charCols.indexOf(col1) === -1)  charCols.push(col1)  
                    //let nyb1 = charCols.indexOf(col1)                    

                    let col2 = palette.findIndex(a => {
                        return (
                            png.data[j+0] === a.red &&
                            png.data[j+1] === a.green &&
                            png.data[j+2] === a.blue &&
                            png.data[j+3] === a.alpha
                        );
                    })   

                    //originalPalIndex.push(col2)
                    //if(charCols.indexOf(col2) === -1)  charCols.push(col2) 
                    //let nyb2 = charCols.indexOf(col2)

                    //push colors in this order so they can be turned into bytes easily alter

                    if(col1 > 0xf || col2 > 0xf) {
                        throw(new Error(`Too many colors in this char: $${(y * hei + x * wid).toString(16)}   ${x},${y},${charCols.length}`))
                    }

                    charCols.push(( col2 << 4 ) + col1)
                }
            }

            let charStr = JSON.stringify(charCols)

            let uniqueIndex = uniques.findIndex(a => {
                return (
                    charStr === a.cstr
                );
            })

            if (uniqueIndex == -1) {
                let uniqueChr = {
                    cstr: charStr,
                    data: charCols
                }

                uniqueIndex = uniques.length

                uniques.push(uniqueChr)
            }

            remap[charIndx] = uniqueIndex
        }
    }

    console.log("found " + uniques.length + " chars / " + remap.length)

    return { uniques, remap }
}

function fetchLevels(ldtk) {
    // return a list of tilesets
    //
    let levels = []

    console.log("*-----------------------------------")
    console.log("parsing levels")

    let levelCount = ldtk.levels.length
    console.log("levelCount = " + levelCount)

    for(var lv = 0; lv < levelCount; lv++) {
        let level = ldtk.levels[lv]
        console.log("level[" + lv + "] name = " + level.identifier)

        let layers = []

        let layerCount = ldtk.levels[lv].layerInstances.length
        console.log("\tlayerCount = " + layerCount)

        for(var l=0; l<layerCount; l++) {
            let layer = ldtk.defs.layers[l]
            console.log("\tlayer[" + l + "] name = " + layer.identifier)

            let map = fetchMap(lv, l, ldtk)

            layers.push(map)
        }

        console.log("\tadded layers = " + layers.length)
        levels.push({layers:layers})
    }

    console.log("added total levels = " + levels.length)
    return levels
}


function fetchMap(levelIndx, layerIndx, ldtk)  {
    let map = []

    let data = ldtk.levels[levelIndx].layerInstances[layerIndx]
    let width = data.__cWid
    let height = data.__cHei
    let size = data.__gridSize

    console.log("\twidth = " + width + " height = " + height + " size = " + size)

    for(var i = 0; i < width; i++) {
        map.push(new Array(height).fill(0))
    }

    console.log("\tgridTiles count = " + data.gridTiles.length)

    for(var i=0; i<data.gridTiles.length; i++) {
        let x=data.gridTiles[i].px[0] / size
        let y=data.gridTiles[i].px[1] / size

        map[x][y] = data.gridTiles[i].t
    }

    // for(var i = 0; i < width; i++) {
    //     console.log("map [" + i + "] " + map[i])
    // }

    return {width, height, size, map}
}

function saveTilesets(tilesets) {

    console.log("*-----------------------------------")
    console.log("saving tilesets")

    for(var ts = 0; ts < tilesets.length; ts++) {
        console.log("\tsaving tileset '" + tilesets[ts].name + "' UID = " + tilesets[ts].uid)

        //SAVE PALETTE
        savePalette(ts, tilesets[ts].pal);
        //SAVE CHARS
        saveChars(ts, tilesets[ts].chrs);
        //SAVE TILES
        saveTiles(ts, tilesets[ts].tiles)
    }
}

function saveMap(map) {
    let basename = path.basename(argv.input)
    let ext = path.extname(argv.input)
    let name = basename.substring(0,basename.length - ext.length)
    let filename = path.resolve(argv.output, name+"_map.bin")

    console.log("save map: ", filename)

    let out = []
    out.push(map.width & 0xff)
    out.push((map.width >> 8) & 0xff)
    out.push(map.height & 0xff)
    out.push((map.height >> 8) & 0xff)    
    out.push((map.size / (argv.ncm ? 16 : 8)) & 0xff)    
    out.push((map.size / 8) & 0xff)       
    for(var y=0; y<map.height; y++) {
        for(var x=0; x<map.width; x++) {
            out.push(map.map[x][y] & 0xff)
            out.push((map.map[x][y] >> 8) & 0xff)
        }
    }
    fs.writeFileSync(filename, Buffer.from(out))
}

function savePalette(indx, pal) {
    let basename = path.basename(argv.input)
    let ext = path.extname(argv.input)
    let name = basename.substring(0,basename.length - ext.length)
    let filename = path.resolve(argv.output, name+indx+"_pal.bin")

    console.log("save pal: ", filename)

    let out = []
    for(var r = 0; r < pal.r.length; r++) {
        out.push(pal.r[r])
    }
    for(var g = 0; g < pal.g.length; g++) {
        out.push(pal.g[g])
    }
    for(var b = 0; b < pal.b.length; b++) {
        out.push(pal.b[b])
    }

    fs.writeFileSync(filename, Buffer.from(out))
}

function saveChars(indx, chars) {
    let basename = path.basename(argv.input)
    let ext = path.extname(argv.input)
    let name = basename.substring(0,basename.length - ext.length)
    let filename = path.resolve(argv.output, name+indx+"_chr.bin")

    console.log("save chars: ", filename)

    let out = []
    for(var c = 0; c < chars.uniques.length; c++) {
        for(var i = 0; i < chars.uniques[c].data.length; i++) {
            out.push(chars.uniques[c].data[i])
        }
    }
    fs.writeFileSync(filename, Buffer.from(out))
}

function saveTiles(indx, tiles) {
    let basename = path.basename(argv.input)
    let ext = path.extname(argv.input)
    let name = basename.substring(0,basename.length - ext.length)
    let filename = path.resolve(argv.output, name+indx+"_tiles.bin")

    console.log("save tiles: ", filename)

    let out = []
    for(var c = 0; c < tiles.uniques.length; c++) {
        for(var i = 0; i < tiles.uniques[c].data.length; i++) {
            out.push(tiles.uniques[c].data[i] & 0xff)
            out.push((tiles.uniques[c].data[i] >> 8) & 0xff)
        }
    }
    fs.writeFileSync(filename, Buffer.from(out))
}

function saveLevels(levels, tilesets) {
    let basename = path.basename(argv.input)
    let ext = path.extname(argv.input)
    let name = basename.substring(0,basename.length - ext.length)

    console.log("*-----------------------------------")
    console.log("saving levels")

    console.log("\tlevels = " + levels.length)

    for(var lv = 0; lv < levels.length; lv++) {
        let level = levels[lv]

        console.log("\t\tlayers = " + level.layers.length)

        for(var l=0; l<level.layers.length; l++) {
            let layer = level.layers[l]

            let filename = path.resolve(argv.output, name+"_LV"+lv+"L"+l+"_map.bin")

            let out = []
            for(var y=0; y<layer.height; y++) {
                for(var x=0; x<layer.width; x++) {
                    // let remapped = tilesets[0].tiles.remap[layer.map[x][y]]
                    let remapped = layer.map[x][y]

                    out.push(remapped & 0xff)
                    out.push((remapped >> 8) & 0xff)
                }
            }

            fs.writeFileSync(filename, Buffer.from(out))
        }
    }

}