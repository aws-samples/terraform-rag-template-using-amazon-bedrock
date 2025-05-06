# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
FROM public.ecr.aws/lambda/python:3.12

RUN  dnf install -y libgomp &&\
     pip3 install --no-cache-dir --upgrade pip &&\
     pip3 install --no-cache-dir build &&\
     dnf -y clean all &&\
     rm -rf /var/cache

COPY ./requirements.txt ./

RUN pip3 install --no-cache-dir -r requirements.txt -t .

COPY . .

# Needed for Excel loader
RUN python -c "import nltk;nltk.download('punkt', download_dir='/usr/share/nltk_data');nltk.download('averaged_perceptron_tagger', download_dir='/usr/share/nltk_data')"

CMD ["handler.lambda_handler"]
