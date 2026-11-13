// Pulls the full game executable out of the original RAR archive (the build keeps only that file).
//   node unrar.mjs <archive.rar> <output dir>
import { createExtractorFromFile } from "node-unrar-js";

const [, , rar, outDir] = process.argv;
const extractor = await createExtractorFromFile({ filepath: rar, targetPath: outDir });
const wanted = (h) => !h.flags.directory && /FableStrike2\.exe$/i.test(h.name) && h.unpSize > 300e6;
const names = [...extractor.extract({ files: wanted }).files].map((f) => f.fileHeader.name);
console.log("extracted:", names.join(", ") || "nothing");
if (names.length === 0) process.exit(1);
