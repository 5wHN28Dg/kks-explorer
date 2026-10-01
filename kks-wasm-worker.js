// Encoding a photo to JPEG XL off the page's thread (decision 0037): {id, rgba, width, height, distance, effort} →
// {id, jxl} or {id, error}.
import {jxlEncode} from '/kks-wasm.js';
onmessage = async e => {
  const {id, rgba, width, height, distance, effort} = e.data;
  try { const jxl = await jxlEncode(new Uint8Array(rgba), width, height, distance, effort); postMessage({id, jxl}, [jxl.buffer]) }
  catch (err) { postMessage({id, error: String(err.message || err)}) }
};
