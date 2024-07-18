# Terraform RAG template with Amazon Bedrock

This repository contains a Terraform implementation of a simple Retrieval-Augmented Generation (RAG) use case using [Amazon Titan V2](https://docs.aws.amazon.com/bedrock/latest/userguide/titan-embedding-models.html) as the embedding model and [Claude 3](https://aws.amazon.com/de/bedrock/claude/) as the text generation model, both on [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html). This sample follows the user journey described below:

1. The user manually uploads a file to Amazon S3, such as a Microsoft Excel or PDF document. The supported file types can be found here.
2. The content of the file is extracted and embedded into a knowledge database based on a serverless [Amazon Aurora with PostgreSQL](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/Aurora.AuroraPostgreSQL.html).
3. When the user engages with the text generation model, it utilizes previously uploaded files to enhance the interaction through retrieval augmentation.


## Architecture


![](/media/bedrock-rag-template.drawio.svg)


1. Whenever an object is created in the [Amazon S3 bucket](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Welcome.html) `bedrock-rag-template-<account_id>`, an [Amazon S3 notification](https://docs.aws.amazon.com/AmazonS3/latest/userguide/EventNotifications.html) invokes the [Amazon Lambda function](https://docs.aws.amazon.com/lambda/latest/dg/welcome.html) `data-ingestion-processor`.

2. The Amazon Lambda function `data-ingestion-processor` is based on a Docker image stored in the [Amazon ECR repository](https://docs.aws.amazon.com/AmazonECR/latest/userguide/what-iss-ecr.html) `bedrock-rag-template`. The function uses the [LangChain S3FileLoader](https://python.langchain.com/v0.1/docs/integrations/document_loaders/aws_s3_file/) to read the file as a [LangChain Document](https://api.python.langchain.com/en/v0.0.339/schema/langchain.schema.document.Document.html). Then, the [LangChain RecursiveTextSplitter](https://python.langchain.com/v0.1/docs/modules/data_connection/document_transformers/recursive_text_splitter/) chunks each document, given a `CHUNK_SIZE` and a `CHUNK_OVERLAP` which depends on the max token size of the embedding model, the Amazon Titan Text Embedding V2. Next, the Lambda function invokes the embedding model on [Amazon Bedrock](https://docs.aws.amazon.com/bedrock/latest/userguide/what-is-bedrock.html) to embed the chunks into numerical vector representations. Lastly, these vectors are stored in the Amazon Aurora PostgreSQL database. To access the Amazon Aurora database, the Lambda function first retrieves the username and password from Amazon Secrets Manager.

3. On the [Amazon SageMaker notebook instance](https://docs.aws.amazon.com/sagemaker/latest/dg/nbi.html) `aws-sample-bedrock-rag-template`, the user can write a question prompt. The code invokes Claude 3 on Amazon Bedrock and provides the knowledge base information to the context of the prompt. As a result, Claude 3 answers using the information in the documents.


### Networking & Security

The Amazon Lambda function `data-ingestion-processor` resides in a private subnet within the VPC and it is not allowed to send traffic to the public internet due its security group. As a result, the traffic to Amazon S3 and Amazon Bedrock is routed through the VPC endpoints only. Consequently, the traffic does not traverse the public internet, which reduces latency and adds an additional layer of security at the networking level.

All the resources and data are encrypted whenever applicable using the Amazon KMS Key with the alias `aws-sample/bedrock-rag-template`.

While this sample can be deployed into any AWS Region, we recommend to use `us-east-1` or `us-west-1` due to the availability of foundation and embedding models in Amazon Bedrock at the time of publishing (see [Model support by AWS Region](https://docs.aws.amazon.com/bedrock/latest/userguide/models-regions.html) for an updated list of Amazon Bedrock foundation model support in AWS Regions). See the section [Next steps](#next-steps) which provides pointers on how to use this solution with other AWS Regions.


## Prerequisites

### Amazon Web Services

To run this sample, make sure that you have an active AWS account and that you have access to a sufficiently strong IAM role in the Management console and in the CLI.

[Enable model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html) for the required LLMs in the Amazon Bedrock Console of your AWS account.
The following models are needed for this example:

* `amazon.titan-embed-text-v2:0`
* `anthropic.claude-3-sonnet-20240229-v1:0`

### Required software

The following software tools are required in order to deploy this repository:

* [Terraform](https://www.terraform.io/):

```shell
❯ terraform --version
Terraform v1.8.4
on linux_amd64
+ provider registry.terraform.io/hashicorp/aws v5.50.0
+ provider registry.terraform.io/hashicorp/external v2.3.3
+ provider registry.terraform.io/hashicorp/local v2.5.1
+ provider registry.terraform.io/hashicorp/null v3.2.2
```

* [Docker](https://docs.docker.com/manuals/)

```shell
❯ docker --version
Docker version 26.0.0, build 2ae903e86c
```

* [Poetry](https://python-poetry.org/)

```shell
❯ poetry --version
Poetry (version 1.7.1)
```

* [Python3.10](https://www.python.org/downloads/release/python-3100/)

* [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)


## Deployment

This sections explains how to deploy the infrastructure and how to run the demo in a Jupyter notebook.
> **Warning:** The following actions are going to cause costs in the deployed AWS Account.


### Credentials

To deploy this sample, [put the credentials as environment variables](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html#envvars-set) or configure the cli directly.
To test whether setting the credentials was successfully run `aws sts get-caller-identity`. The output should contain the ARN of the user or role that you are signed in as.

### Infrastructure

To deploy the entire infrastructure, run the following commands:

```shell
cd terraform
terraform init
terraform plan -var-file=commons.tfvars  
terraform apply -var-file=commons.tfvars  
```


### Demo in the Jupyter notebook

The end to end demo is presented inside the Jupyter notebook. Follow the steps below to run the demo by yourself.

#### Preparation

The infrastructure deployment provisions an Amazon SageMaker notebook instance inside the VPC and with the permissions to access the PostgreSQL Aurora database. Once the previous infrastructure deployment has succeeded, follow the subsequent steps to run the demo in a Jupyter notebook:

1. Log into the AWS management console of the account where the infrastructure is deployed
2. Open the SageMaker notebook instance `aws-sample-bedrock-rag-template`.
3. Move the [rag_demo.ipynb](/rag_demo.ipynb) Jupyter notebook onto the SageMaker notebook instance via drag & drop.
4. Open the [rag_demo.ipynb](/rag_demo.ipynb) on the SageMaker notebook instance and choose the `conda_python3` kernel.
5. Run the cells of the notebook to run the demo.

#### Running the demo

The Jupyter notebook guides the reader through the following process:

- Installing requirements
- Embedding definition
- Database connection
- Data ingestion
- Retrieval augmented text generation
- Relevant document queries


### Clean up

To destroy the infrastructure run `terraform destroy -var-file=commons.tfvars`.


## Testing

### Prerequisites - virtual Python environment

Make sure that the dependencies in the [pyproject.toml](/pyproject.toml) are aligned with the [requirements](/python/src/handlers/data_ingestion_processor/requirements.txt) of the Amazon Lambda `data-ingestion-processor`.

Install the dependencies and active the virtual environment:

```shell
poetry lock
poetry install
poetry shell

```

### Run the test


```shell
python -m pytest .
```



## Next steps


### Deployment to other AWS Regions

There are two possible ways to deploy this stack to AWS Regions other than `us-east-1` and `us-west-1`. You can configure the deployment AWS Region in the [`commons.tfvars`](/terraform/commons.tfvars) file. For cross-region foundation model access, consider the following options:

1. **Traversing the public internet**: if the traffic can traverse the public the public internet, add internet gateways to the VPC and adjust the security group assigned to the Amazon Lambda function `data-ingestion-processor` and the SageMaker notebook instance to allow outbound traffic to the public internet.
2. **NOT traversing the public internet**: deploy this sample to any AWS Region different from `us-east-1` or `us-west-1`. In `us-east-1` or `us-west-1`, create an additional VPC including a VPC endpoint for `bedrock-runtime`. Then, peer the VPC using a VPC peering or a transit gateway to the application VPC. Lastly, when configuring the `bedrock-runtime` boto3 client in any AWS Lambda function outside of `us-east-1` or `us-west-1`, pass the private DNS name of the VPC endpoint for `bedrock-runtime` in `us-east-1` or `us-west-1` as `endpoint_url` to the boto3 client. For the VPC peering solution, one can leverage the module [Terraform AWS VPC Peering](https://github.com/grem11n/terraform-aws-vpc-peering).

## Dependencies and Licenses

This project is licensed under the MIT License - see the `LICENSE` file for details.

### Dependencies

* [AWS Lambda Terraform module](https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest)
* [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest)
* [Terraform](https://developer.hashicorp.com/terraform)
* [Docker Engine](https://docs.docker.com/engine/)


## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.
