# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
import os

import pytest
from langchain.schema.document import Document


@pytest.mark.parametrize(
    "chunk_size, chunk_overlap, documents, expected_error",
    [
        (
            1000,
            100,
            [
                Document(page_content="This is a test document. " * 100),
                Document(page_content="Another test document. " * 100),
            ],
            None,
        ),
        # (50, 100, [Document(page_content="Short doc. " * 10)], ValueError)  # chunk_size < chunk_overlap should raise an error
    ],
)
def test_chunk_documents(chunk_size, chunk_overlap, documents, expected_error):
    """Test chunk_documents function with different chunk sizes and overlaps."""
    os.environ["CHUNK_SIZE"] = str(chunk_size)
    os.environ["CHUNK_OVERLAP"] = str(chunk_overlap)

    from python.src.handlers.data_ingestion_processor.handler import chunk_documents

    if expected_error:
        with pytest.raises(expected_error):
            chunk_documents(documents)
    else:
        expected_num_chunks = sum(
            (len(doc.page_content) - chunk_overlap) // (chunk_size - chunk_overlap) + 1
            for doc in documents
        )

        result = chunk_documents(documents)

        # Assert the number of chunks is as expected
        assert len(result) == expected_num_chunks

        # Assert the content of the chunks
        for chunk in result:
            assert len(chunk.page_content) <= chunk_size
            assert any(chunk.page_content in doc.page_content for doc in documents)
