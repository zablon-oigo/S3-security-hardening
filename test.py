import os
import boto3
import tempfile

BUCKET_NAME=os.environ['BUCKET_NAME']

def lambda_handler(event, context):
    s3_client=boto3.client('s3')
    file_content='Lorem ipsum dolor sit amet, consectetuer adipiscing elit. Aenean commodo ligula eget dolor. Aenean massa. Cum sociis natoque penatibus et magnis dis parturient montes, nascetur ridiculus mus. Donec quam felis, ultricies nec, pellentesque eu, pretium quis, sem.'
    temp_file=tempfile.NamedTemporaryFile(delete=False)
    with opent(temp_file.name,'w')as f:
        f.write(file_content)

    s3_client.upload_file(temp_file.name,BUCKET_NAME,'test.txt')
    s3_client.download_file(BUCKET_NAME,'test.txt',temp_file.name)

    with open(temp_file.name,'r')as f:
        file_content=f.read()
        print(file_content)