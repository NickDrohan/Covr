"""OCR processing using Tesseract."""

from typing import Dict, List, Any, Optional, Tuple
from PIL import Image
import pytesseract
from pytesseract import Output
import logging
from collections import defaultdict

from app.models import (
    Block, Paragraph, Line, Word, Chunks,
    EngineInfo, OCRResponse, ImageInfo, TimingInfo, RawOutput
)
from app.utils import get_tesseract_version, Timer

logger = logging.getLogger(__name__)


def run_tesseract(
    img: Image.Image,
    lang: str = "eng",
    psm: int = 3,
    oem: int = 1
) -> Dict[str, Any]:
    """Run Tesseract OCR and get TSV data as dictionary.
    
    Args:
        img: PIL Image to process
        lang: Tesseract language code
        psm: Page segmentation mode (0-13)
        oem: OCR Engine Mode (0-3)
        
    Returns:
        Dictionary with TSV data columns as keys and lists as values
    """
    config = f"--psm {psm} --oem {oem}"
    
    # Get data as dictionary (similar to pandas DataFrame structure)
    data = pytesseract.image_to_data(
        img,
        lang=lang,
        config=config,
        output_type=Output.DICT
    )
    
    return data


def get_hocr(
    img: Image.Image,
    lang: str = "eng",
    psm: int = 3,
    oem: int = 1
) -> str:
    """Get hOCR output from Tesseract.
    
    Args:
        img: PIL Image
        lang: Language code
        psm: Page segmentation mode
        oem: OCR engine mode
        
    Returns:
        hOCR XML string
    """
    config = f"--psm {psm} --oem {oem}"
    return pytesseract.image_to_pdf_or_hocr(
        img,
        lang=lang,
        config=config,
        extension='hocr'
    ).decode('utf-8')


def get_tsv_string(
    img: Image.Image,
    lang: str = "eng",
    psm: int = 3,
    oem: int = 1
) -> str:
    """Get TSV output from Tesseract as string.
    
    Args:
        img: PIL Image
        lang: Language code
        psm: Page segmentation mode
        oem: OCR engine mode
        
    Returns:
        TSV string
    """
    config = f"--psm {psm} --oem {oem}"
    return pytesseract.image_to_data(
        img,
        lang=lang,
        config=config,
        output_type=Output.STRING
    )


def parse_tsv_to_hierarchy(data: Dict[str, Any]) -> Tuple[Chunks, str, List[str], int]:
    """Parse Tesseract TSV data into hierarchical structure.
    
    Args:
        data: Dictionary from pytesseract.image_to_data with Output.DICT
        
    Returns:
        Tuple of (Chunks, full_text, warnings, empty_word_count)
    """
    warnings = []
    empty_word_count = 0
    
    # Group data by block -> paragraph -> line -> word
    # Structure: {block_num: {par_num: {line_num: [word_data]}}}
    hierarchy: Dict[int, Dict[int, Dict[int, List[Dict]]]] = defaultdict(
        lambda: defaultdict(lambda: defaultdict(list))
    )
    
    n_boxes = len(data.get('text', []))
    
    for i in range(n_boxes):
        # Skip entries without valid level
        level = data['level'][i]
        if level != 5:  # Level 5 = word
            continue
        
        text = data['text'][i].strip()
        conf = data['conf'][i]
        
        # Skip empty text
        if not text:
            empty_word_count += 1
            continue
        
        block_num = data['block_num'][i]
        par_num = data['par_num'][i]
        line_num = data['line_num'][i]
        word_num = data['word_num'][i]
        
        # Bounding box
        left = data['left'][i]
        top = data['top'][i]
        width = data['width'][i]
        height = data['height'][i]
        
        word_data = {
            'word_num': word_num,
            'text': text,
            'conf': float(conf) if conf != -1 else None,
            'bbox': [left, top, left + width, top + height]
        }
        
        hierarchy[block_num][par_num][line_num].append(word_data)
    
    # Build the hierarchical structure
    blocks = []
    full_text_parts = []
    
    for block_num in sorted(hierarchy.keys()):
        block_paragraphs = []
        block_bbox = None
        
        for par_num in sorted(hierarchy[block_num].keys()):
            par_lines = []
            par_bbox = None
            
            for line_num in sorted(hierarchy[block_num][par_num].keys()):
                words_data = hierarchy[block_num][par_num][line_num]
                
                # Sort words by word_num
                words_data.sort(key=lambda w: w['word_num'])
                
                # Build Word objects
                words = []
                line_text_parts = []
                line_bbox = None
                line_conf_sum = 0
                line_conf_count = 0
                
                for wd in words_data:
                    word = Word(
                        word_num=wd['word_num'],
                        bbox=wd['bbox'],
                        confidence=wd['conf'],
                        text=wd['text']
                    )
                    words.append(word)
                    line_text_parts.append(wd['text'])
                    
                    # Update line bbox
                    if line_bbox is None:
                        line_bbox = list(wd['bbox'])
                    else:
                        line_bbox[0] = min(line_bbox[0], wd['bbox'][0])
                        line_bbox[1] = min(line_bbox[1], wd['bbox'][1])
                        line_bbox[2] = max(line_bbox[2], wd['bbox'][2])
                        line_bbox[3] = max(line_bbox[3], wd['bbox'][3])
                    
                    # Track confidence for line average
                    if wd['conf'] is not None:
                        line_conf_sum += wd['conf']
                        line_conf_count += 1
                
                line_text = " ".join(line_text_parts)
                line_confidence = (line_conf_sum / line_conf_count) if line_conf_count > 0 else None
                
                line = Line(
                    line_num=line_num,
                    bbox=line_bbox or [0, 0, 0, 0],
                    confidence=line_confidence,
                    text=line_text,
                    words=words
                )
                par_lines.append(line)
                full_text_parts.append(line_text)
                
                # Update paragraph bbox
                if par_bbox is None:
                    par_bbox = list(line_bbox) if line_bbox else [0, 0, 0, 0]
                elif line_bbox:
                    par_bbox[0] = min(par_bbox[0], line_bbox[0])
                    par_bbox[1] = min(par_bbox[1], line_bbox[1])
                    par_bbox[2] = max(par_bbox[2], line_bbox[2])
                    par_bbox[3] = max(par_bbox[3], line_bbox[3])
            
            paragraph = Paragraph(
                par_num=par_num,
                bbox=par_bbox or [0, 0, 0, 0],
                lines=par_lines
            )
            block_paragraphs.append(paragraph)
            
            # Update block bbox
            if block_bbox is None:
                block_bbox = list(par_bbox) if par_bbox else [0, 0, 0, 0]
            elif par_bbox:
                block_bbox[0] = min(block_bbox[0], par_bbox[0])
                block_bbox[1] = min(block_bbox[1], par_bbox[1])
                block_bbox[2] = max(block_bbox[2], par_bbox[2])
                block_bbox[3] = max(block_bbox[3], par_bbox[3])
        
        # Calculate block confidence as average of all words
        block_conf = None  # Could calculate if needed
        
        block = Block(
            block_num=block_num,
            bbox=block_bbox or [0, 0, 0, 0],
            confidence=block_conf,
            paragraphs=block_paragraphs
        )
        blocks.append(block)
    
    chunks = Chunks(blocks=blocks)
    full_text = "\n".join(full_text_parts)
    
    if empty_word_count > 0:
        warnings.append(f"Dropped {empty_word_count} empty word entries")
    
    return chunks, full_text, warnings, empty_word_count


def perform_ocr(
    img: Image.Image,
    lang: str = "eng",
    psm: int = 3,
    oem: int = 1,
    return_format: str = "json",
    request_id: str = "",
    image_width: int = 0,
    image_height: int = 0,
    processed: bool = True,
    preprocessing_notes: List[str] = None,
    timing_decode: float = 0,
    timing_preprocess: float = 0
) -> OCRResponse:
    """Perform OCR and return structured response.
    
    Args:
        img: Preprocessed PIL Image
        lang: Tesseract language code
        psm: Page segmentation mode
        oem: OCR engine mode
        return_format: One of "json", "tsv", "hocr", "both"
        request_id: Request ID for tracking
        image_width: Processed image width
        image_height: Processed image height
        processed: Whether preprocessing was applied
        preprocessing_notes: Notes from preprocessing
        timing_decode: Time spent decoding image (ms)
        timing_preprocess: Time spent preprocessing (ms)
        
    Returns:
        OCRResponse with structured OCR data
    """
    if preprocessing_notes is None:
        preprocessing_notes = []
    
    warnings = []
    
    # Run OCR
    with Timer() as ocr_timer:
        tsv_data = run_tesseract(img, lang, psm, oem)
    
    timing_ocr = ocr_timer.elapsed_ms
    
    # Parse TSV into hierarchy
    chunks, full_text, parse_warnings, _ = parse_tsv_to_hierarchy(tsv_data)
    warnings.extend(parse_warnings)
    
    # Get raw outputs if requested
    raw = RawOutput()
    if return_format in ("tsv", "both"):
        raw.tsv = get_tsv_string(img, lang, psm, oem)
    if return_format in ("hocr", "both"):
        raw.hocr = get_hocr(img, lang, psm, oem)
    
    # Build response
    total_timing = timing_decode + timing_preprocess + timing_ocr
    
    response = OCRResponse(
        request_id=request_id,
        engine=EngineInfo(
            name="tesseract",
            version=get_tesseract_version(),
            lang=lang,
            psm=psm,
            oem=oem
        ),
        image=ImageInfo(
            width=image_width,
            height=image_height,
            processed=processed,
            notes=preprocessing_notes
        ),
        timing_ms=TimingInfo(
            decode=round(timing_decode, 2),
            preprocess=round(timing_preprocess, 2),
            ocr=round(timing_ocr, 2),
            total=round(total_timing, 2)
        ),
        text=full_text,
        chunks=chunks,
        raw=raw,
        warnings=warnings
    )
    
    return response
