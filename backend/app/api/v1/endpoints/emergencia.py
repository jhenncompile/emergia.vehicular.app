import logging
from typing import Optional
from fastapi import APIRouter, UploadFile, File, HTTPException, status
from app.services.ai_service import (
    AIService,
    HuggingFaceAPIError,
    AIServiceError,
)

# Configure logging
logger = logging.getLogger(__name__)

router = APIRouter()
ai_service: Optional[AIService] = None

# Allowed file types for validation
ALLOWED_AUDIO_FORMATS = {
    "audio/mpeg",
    "audio/wav",
    "audio/ogg",
    "audio/flac",
    "audio/mp4",
}
ALLOWED_IMAGE_FORMATS = {"image/jpeg", "image/png", "image/webp"}
MAX_AUDIO_SIZE_MB = 25  # Reasonable limit for audio files
MAX_IMAGE_SIZE_MB = 10  # Reasonable limit for image files


def _get_ai_service() -> AIService:
    """Initialize AI service lazily so the API can boot without HF_API_TOKEN."""
    global ai_service
    if ai_service is None:
        ai_service = AIService()
    return ai_service


def _validate_file_size(file: UploadFile, max_size_mb: int) -> None:
    """
    Validate uploaded file size to prevent memory exhaustion.

    Args:
        file (UploadFile): The uploaded file to validate.
        max_size_mb (int): Maximum allowed file size in megabytes.

    Raises:
        HTTPException: If file size exceeds the limit.
    """
    max_size_bytes = max_size_mb * 1024 * 1024
    if file.size and file.size > max_size_bytes:
        logger.warning(
            f"File size validation failed: {file.filename} "
            f"({file.size} bytes) exceeds {max_size_mb}MB limit"
        )
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"File size exceeds {max_size_mb}MB limit.",
        )


def _validate_audio_file(file: UploadFile) -> None:
    """
    Validate audio file format and size.

    Args:
        file (UploadFile): The audio file to validate.

    Raises:
        HTTPException: If file format is invalid or size exceeds limit.
    """
    if file.content_type not in ALLOWED_AUDIO_FORMATS:
        logger.warning(
            f"Invalid audio format: {file.content_type} for {file.filename}"
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Invalid audio format. Supported formats: "
                f"{', '.join(ALLOWED_AUDIO_FORMATS)}"
            ),
        )
    _validate_file_size(file, MAX_AUDIO_SIZE_MB)


def _validate_image_file(file: UploadFile) -> None:
    """
    Validate image file format and size.

    Args:
        file (UploadFile): The image file to validate.

    Raises:
        HTTPException: If file format is invalid or size exceeds limit.
    """
    if file.content_type not in ALLOWED_IMAGE_FORMATS:
        logger.warning(
            f"Invalid image format: {file.content_type} for {file.filename}"
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Invalid image format. Supported formats: "
                f"{', '.join(ALLOWED_IMAGE_FORMATS)}"
            ),
        )
    _validate_file_size(file, MAX_IMAGE_SIZE_MB)


@router.post("/reportar")
async def reportar_emergencia(
    audio: UploadFile = File(..., description="Audio file of emergency report"),
    imagen: UploadFile = File(..., description="Image file of incident scene"),
) -> dict:
    """
    Report emergency incident with multimodal analysis.

    CU-09: Reportar Emergencia (Emergency Report)

    This endpoint processes emergency reports containing both audio and image
    files. It uses AI models to transcribe audio and detect objects in images,
    then generates a priority assessment for the incident.

    Memory-efficient implementation using streaming file reads without
    temporary storage to work within Render's 512MB RAM constraint.

    Args:
        audio (UploadFile): Audio recording of the emergency (MP3, WAV, OGG, FLAC).
        imagen (UploadFile): Image of the incident scene (JPEG, PNG, WebP).

    Returns:
        dict: Emergency report assessment containing:
            - status (str): Overall processing status ("success", "partial", "error")
            - transcription (str): Transcribed text from audio
            - detections (list): Raw detected objects from image analysis
            - detection_summary (list): Clean list of detected object labels
            - priority (str): Priority level ("Alta", "Media", "Baja")
            - message (str): Human-readable processing summary

    Raises:
        HTTPException: If file validation fails, processing fails, or API errors occur.

    Example:
        ```python
        curl -X POST "http://localhost:8000/api/v1/emergencia/reportar" \\
          -F "audio=@emergency.mp3" \\
          -F "imagen=@scene.jpg"
        ```
    """
    logger.info(
        f"Emergency report received: "
        f"audio={audio.filename}, image={imagen.filename}"
    )

    try:
        # Validate input files
        _validate_audio_file(audio)
        _validate_image_file(imagen)

        # Read files into memory as bytes (no temporary storage)
        logger.debug("Reading audio file into memory")
        audio_data = await audio.read()
        if not audio_data:
            logger.error("Audio file is empty")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Audio file is empty. Please provide a valid audio file.",
            )

        logger.debug("Reading image file into memory")
        imagen_data = await imagen.read()
        if not imagen_data:
            logger.error("Image file is empty")
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Image file is empty. Please provide a valid image file.",
            )

        logger.info(
            f"Processing files: audio={len(audio_data)} bytes, "
            f"image={len(imagen_data)} bytes"
        )

        # Process emergency report with AI models
        resultado = _get_ai_service().process_emergency_report(
            audio_data,
            imagen_data,
        )

        # Format response
        response_message = (
            f"Emergency report processed successfully. "
            f"Priority level: {resultado['priority']}. "
            f"Status: {resultado['status']}."
        )

        logger.info(
            f"Emergency report processed: "
            f"priority={resultado['priority']}, "
            f"detections={len(resultado['detection_summary'])}"
        )

        return {
            "status": "success",
            "data": {
                "transcription": resultado["transcription"],
                "detections": resultado["detections"],
                "detection_summary": resultado["detection_summary"],
                "priority": resultado["priority"],
                "processing_status": resultado["status"],
            },
            "message": response_message,
        }

    except HTTPException:
        # Re-raise HTTP exceptions as-is
        raise

    except HuggingFaceAPIError as e:
        logger.error(f"AI service error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(e),
        )

    except AIServiceError as e:
        logger.error(f"AI service initialization error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="AI service is not properly configured. Please contact support.",
        )

    except Exception as e:
        logger.error(f"Unexpected error processing emergency report: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=(
                "An unexpected error occurred while processing your report. "
                "Please try again later."
            ),
        )
