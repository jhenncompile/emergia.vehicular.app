import os
import logging
import requests
from typing import Dict, Any, Optional
from dotenv import load_dotenv

load_dotenv()

# Configure logging
logger = logging.getLogger(__name__)


class AIServiceError(Exception):
    """Base exception for AI service errors."""
    pass


class HuggingFaceAPIError(AIServiceError):
    """Exception raised when Hugging Face API call fails."""
    pass


class AIService:
    """
    Service to interact with AI models via Hugging Face Inference API.

    This service handles multimodal emergency report processing using:
    - OpenAI Whisper Tiny for audio transcription
    - Facebook DETR ResNet-50 for object detection in images

    The service is designed to be memory-efficient for Render's 512MB RAM
    constraint by processing files as byte streams without temporary storage.

    Attributes:
        api_token (str): Hugging Face API token for authentication.
        audio_url (str): API endpoint for audio transcription model.
        vision_url (str): API endpoint for vision/object detection model.
        timeout (int): Request timeout in seconds.
    """

    def __init__(
        self,
        audio_model: str = "openai/whisper-large-v3",
        vision_model: str = "facebook/detr-resnet-50",
        timeout: int = 30,
    ):
        """
        Initialize the AIService with Hugging Face Inference API credentials.

        Args:
            audio_model (str): Hugging Face model ID for audio processing.
                Defaults to "openai/whisper-tiny".
            vision_model (str): Hugging Face model ID for vision processing.
                Defaults to "facebook/detr-resnet-50".
            timeout (int): Request timeout in seconds. Defaults to 30.

        Raises:
            AIServiceError: If HF_API_TOKEN environment variable is not set.
        """
        self.api_token = os.getenv("HF_API_TOKEN")
        if not self.api_token:
            logger.error("HF_API_TOKEN not configured in environment")
            raise AIServiceError(
                "Hugging Face API token not configured. "
                "Please set HF_API_TOKEN environment variable."
            )

        audio_model = os.getenv("HF_AUDIO_MODEL", audio_model)
        vision_model = os.getenv("HF_VISION_MODEL", vision_model)

        self.headers = {"Authorization": f"Bearer {self.api_token}"}
        base_url = os.getenv(
            "HF_INFERENCE_BASE_URL",
            "https://router.huggingface.co/hf-inference/models",
        ).rstrip("/")
        self.audio_url = f"{base_url}/{audio_model}"
        self.vision_url = f"{base_url}/{vision_model}"
        self.timeout = timeout
        logger.info("AIService initialized successfully")

    def _make_api_request(
        self,
        url: str,
        file_data: bytes,
        request_type: str = "audio",
        content_type: str | None = None,
    ) -> Dict[str, Any]:
        """
        Make a POST request to Hugging Face Inference API.

        This method handles the HTTP request to the Hugging Face API with
        proper error handling for timeouts, API errors, and malformed responses.

        Args:
            url (str): The Hugging Face API endpoint URL.
            file_data (bytes): The file content as bytes.
            request_type (str): Type of request (audio/vision) for logging.
                Defaults to "audio".

        Returns:
            Dict[str, Any]: The JSON response from the API.

        Raises:
            HuggingFaceAPIError: If the API request fails for any reason.
        """
        try:
            response = requests.post(
                url,
                headers={
                    **self.headers,
                    **({"Content-Type": content_type} if content_type else {}),
                },
                data=file_data,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return response.json()

        except requests.exceptions.Timeout:
            logger.error(
                f"Timeout calling {request_type} API after {self.timeout}s"
            )
            raise HuggingFaceAPIError(
                f"{request_type.capitalize()} processing timed out. "
                f"Please try again."
            )

        except requests.exceptions.ConnectionError as e:
            logger.error(f"Connection error calling {request_type} API: {e}")
            raise HuggingFaceAPIError(
                f"Failed to connect to {request_type} processing service."
            )

        except requests.exceptions.HTTPError as e:
            status_code = e.response.status_code
            response_text = (e.response.text or "").strip()
            if len(response_text) > 300:
                response_text = f"{response_text[:300]}..."
            logger.error(
                f"HTTP error {status_code} calling {request_type} API: "
                f"{e}. Response: {response_text}"
            )
            if status_code == 401:
                raise HuggingFaceAPIError("Invalid Hugging Face API token.")
            elif status_code == 503:
                raise HuggingFaceAPIError(
                    f"{request_type.capitalize()} model is currently unavailable. "
                    "Please try again later."
                )
            else:
                detail = f" Detalle HF: {response_text}" if response_text else ""
                raise HuggingFaceAPIError(
                    f"API error ({status_code}): "
                    f"{request_type.capitalize()} processing failed.{detail}"
                )

        except requests.exceptions.RequestException as e:
            logger.error(f"Request error calling {request_type} API: {e}")
            raise HuggingFaceAPIError(
                f"Unexpected error during {request_type} processing."
            )

        except ValueError as e:
            logger.error(f"Invalid JSON response from {request_type} API: {e}")
            raise HuggingFaceAPIError(
                f"Invalid response from {request_type} processing service."
            )

    def transcribe_audio(
        self,
        audio_data: bytes,
        content_type: str | None = "audio/wav",
    ) -> str:
        """
        Transcribe audio data using Whisper Tiny model.

        Processes audio bytes and returns the transcribed text. Handles
        various error conditions gracefully.

        Args:
            audio_data (bytes): Raw audio file content.

        Returns:
            str: The transcribed text from the audio file.

        Raises:
            HuggingFaceAPIError: If transcription fails.
        """
        logger.debug(f"Starting audio transcription ({len(audio_data)} bytes)")

        try:
            response = self._make_api_request(
                self.audio_url,
                audio_data,
                request_type="audio",
                content_type=content_type,
            )

            transcription = response.get("text", "")
            if not transcription:
                logger.warning("Empty transcription received from API")
                return ""

            logger.debug(f"Transcription successful: {len(transcription)} chars")
            return transcription

        except HuggingFaceAPIError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error during audio transcription: {e}")
            raise HuggingFaceAPIError("Audio transcription failed unexpectedly.")

    def detect_objects_in_image(
        self,
        image_data: bytes,
        content_type: str | None = "image/jpeg",
    ) -> list:
        """
        Detect objects in image data using DETR ResNet-50 model.

        Analyzes an image and returns a list of detected objects with their
        labels, confidence scores, and bounding box information.

        Args:
            image_data (bytes): Raw image file content (JPG, PNG, etc.).

        Returns:
            list: List of detected objects. Each object contains:
                - label (str): Object class label (e.g., "car", "person")
                - score (float): Confidence score (0-1)
                - box (dict): Bounding box coordinates if available
                Returns empty list if no objects detected or API error occurs.

        Raises:
            HuggingFaceAPIError: If object detection fails.
        """
        logger.debug(f"Starting object detection ({len(image_data)} bytes)")

        try:
            response = self._make_api_request(
                self.vision_url,
                image_data,
                request_type="vision",
                content_type=content_type,
            )

            # Handle different response formats from the API
            if isinstance(response, dict) and "error" in response:
                logger.warning(f"API returned error: {response['error']}")
                return []

            # Normalize response to list format
            detections = response if isinstance(response, list) else []

            logger.debug(
                f"Object detection successful: {len(detections)} objects found"
            )
            return detections

        except HuggingFaceAPIError:
            raise
        except Exception as e:
            logger.error(f"Unexpected error during object detection: {e}")
            raise HuggingFaceAPIError("Object detection failed unexpectedly.")

    def process_emergency_report(
        self,
        audio_data: bytes,
        image_data: bytes,
    ) -> Dict[str, Any]:
        """
        Process a multimodal emergency report with audio and image data.

        Combines audio transcription and image analysis to generate a
        comprehensive emergency assessment. Handles individual component
        failures gracefully to ensure partial results are still useful.

        Args:
            audio_data (bytes): Raw audio file content.
            image_data (bytes): Raw image file content.

        Returns:
            Dict[str, Any]: Structured report containing:
                - transcription (str): Transcribed text from audio
                - detections (list): List of detected objects from image
                - detection_summary (list): Clean list of detected object labels
                - priority (str): Priority level ("Alta", "Media", "Baja")
                - status (str): Processing status ("success", "partial", "error")

        Raises:
            HuggingFaceAPIError: If both audio and image processing fail.
        """
        logger.info("Starting multimodal emergency report processing")

        report = {
            "transcription": "",
            "detections": [],
            "detection_summary": [],
            "priority": "Media",
            "status": "error",
        }

        # Process audio
        audio_error = None
        try:
            report["transcription"] = self.transcribe_audio(audio_data)
        except HuggingFaceAPIError as e:
            audio_error = str(e)
            logger.warning(f"Audio processing failed: {audio_error}")

        # Process image
        vision_error = None
        try:
            report["detections"] = self.detect_objects_in_image(image_data)
            # Extract clean labels from detections
            report["detection_summary"] = [
                obj.get("label", "unknown")
                for obj in report["detections"]
                if isinstance(obj, dict)
            ]
        except HuggingFaceAPIError as e:
            vision_error = str(e)
            logger.warning(f"Vision processing failed: {vision_error}")

        # Determine status and priority
        if not audio_error and not vision_error:
            report["status"] = "success"
        elif not audio_error or not vision_error:
            report["status"] = "partial"
        else:
            logger.error("Both audio and image processing failed")
            raise HuggingFaceAPIError(
                "Unable to process emergency report. "
                "Please check file formats and try again."
            )

        # Assess priority based on detections
        emergency_keywords = {"car", "vehicle", "person", "accident", "fire"}
        detected_labels = [d.lower() for d in report["detection_summary"]]
        has_emergency_content = any(
            keyword in detected_labels for keyword in emergency_keywords
        )

        if has_emergency_content or len(report["detection_summary"]) > 2:
            report["priority"] = "Alta"
        elif len(report["detection_summary"]) > 0:
            report["priority"] = "Media"
        else:
            report["priority"] = "Baja"

        logger.info(
            f"Emergency report processed: "
            f"status={report['status']}, priority={report['priority']}"
        )
        return report
