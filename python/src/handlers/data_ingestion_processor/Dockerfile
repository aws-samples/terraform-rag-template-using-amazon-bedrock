# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
FROM public.ecr.aws/lambda/python:3.12

COPY . .
RUN dnf install -y gcc
RUN dnf install -y mesa-libGL
RUN pip install --no-cache-dir -r requirements.txt

# Needed for Excel loader
RUN python -c "import nltk;nltk.download('punkt', download_dir='/usr/share/nltk_data')"
RUN python -c "import nltk;nltk.download('averaged_perceptron_tagger', download_dir='/usr/share/nltk_data')"

CMD ["handler.lambda_handler"]
