# TabCam cloud OCR: one image, two Lambda functions (see locr/handler.py).
# x86_64: PaddlePaddle publishes no Linux ARM wheels for this version on
# PyPI. Paddle's own index has a linux_aarch64 3.3.1 wheel, but with it the
# self-test aborts (SIGABRT) loading the PaddleOCR models (tried 2026-10-14),
# so arm64 Lambda (20% cheaper) waits for a working manylinux aarch64 wheel.
# Debian trixie: Tesseract 5.5 (bookworm's 5.3 reads tab lines far worse).
FROM python:3.12.11-slim-trixie

RUN apt-get update \
 && apt-get install -y --no-install-recommends tesseract-ocr tesseract-ocr-eng libgomp1 libgl1 libglib2.0-0t64 fonts-liberation \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /var/task
COPY requirements.txt .
# RapidOCR also pulls in opencv-python; both install the cv2 package, so the
# build PaddleX requires is reinstalled last, to be the one that's there.
RUN pip install --no-cache-dir -r requirements.txt \
 && pip install --no-cache-dir --force-reinstall --no-deps opencv-contrib-python==4.10.0.84 \
 && python -c "import cv2; assert cv2.__version__ == '4.10.0', cv2.__version__"

# Lambda's file system is read-only but /tmp: the models live in the image,
# and anything the libraries write goes to /tmp.
ENV HOME=/tmp \
    PADDLE_PDX_CACHE_HOME=/opt/paddlex \
    PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True \
    OPENCV_IO_MAX_IMAGE_PIXELS=60000000 \
    PYTHONDONTWRITEBYTECODE=1

COPY locr/ locr/
# Fetches the PaddleOCR models into /opt/paddlex, and fails the build if the
# image can't read a made-up riff.
ARG SELFTEST_MIN=0.8
RUN python -m locr.selftest --min "$SELFTEST_MIN" && chmod -R a+rX /opt/paddlex

ARG LOCR_VERSION=dev
ENV LOCR_VERSION=${LOCR_VERSION}
USER 1000
ENTRYPOINT ["python", "-m", "awslambdaric"]
CMD ["locr.handler.ocr"]
