// Encoding a photo to JPEG XL off the page's thread (decision 0037): {id, rgba, width, height, distance, effort} →
// {id, jxl} or {id, error}.
import {jxlEncode} from '/kks-wasm.js';
// An ImageBitmap instead of rgba (`bitmap`): its pixels are read here, off the page's thread.
onmessage = async e => {
  let {id, rgba, width, height, distance, effort, bitmap} = e.data;
  try {
    if (bitmap) {
      ({width, height} = bitmap);
      const g = new OffscreenCanvas(width, height).getContext('2d');
      g.drawImage(bitmap, 0, 0); bitmap.close();
      rgba = g.getImageData(0, 0, width, height).data.buffer;
    }
    const jxl = await jxlEncode(new Uint8Array(rgba), width, height, distance, effort); postMessage({id, jxl}, [jxl.buffer]) }
  catch (err) { postMessage({id, error: String(err.message || err)}) }
};
