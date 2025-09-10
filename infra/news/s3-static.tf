resource "aws_s3_bucket" "news" {
  bucket = "${var.prefix}-terraform-infra-static-pages"
  force_destroy = true

  # website {
  #   index_document = "index.html"
  #   error_document = "error.html"
  # }
}

locals {
  pages = {
    index = {
      file = "index.html",
      path = "index.html"
    },
    error = {
      file = "error.html",
      path = "error.html"
    }
  }
}

resource "aws_s3_object" "object" {
  for_each = local.pages
  bucket = aws_s3_bucket.news.id
  key    = each.value.file
  source = each.value.path
  content_type = "text/html"
}

resource "aws_s3_bucket_lifecycle_configuration" "bucket_lifecycle" {
  bucket = aws_s3_bucket.news.id

  rule {
    id = "archive_object"

    transition {
      storage_class = "STANDARD_IA"
      days = 30
    }

    transition {
      storage_class = "GLACIER"
      days = 60
    }

    expiration {
      days = 365
    }

    status = "Enabled"
  }
}



resource "aws_s3_bucket_public_access_block" "news" {
  bucket = aws_s3_bucket.news.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "news" {
  bucket = aws_s3_bucket.news.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# resource "aws_s3_bucket_acl" "news" {
#   depends_on = [
# 	aws_s3_bucket_public_access_block.news,
# 	aws_s3_bucket_ownership_controls.news,
#   ]

#   bucket = aws_s3_bucket.news.id
#   acl    = "public-read"
# }

resource "aws_cloudfront_origin_access_control" "s3_oac" {
  name                              = "s3-oac"
  description                       = "oac for s3"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


resource "aws_cloudfront_distribution" "cloudfront" {
  origin {
    domain_name = aws_s3_bucket.news.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.s3_oac.id
    origin_id = "s3-origin"
  }
  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3-origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  custom_error_response {
    error_code = 403
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name = "${var.prefix}-cloudfront"
    createdBy = "infra-${var.prefix}/news"
  }
}

data "aws_iam_policy_document" "oac_policy" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions = ["s3:GetObject"]

    resources = ["${aws_s3_bucket.news.arn}/*"]
  }

}

resource "aws_s3_bucket_policy" "policy" {
  bucket = aws_s3_bucket.news.id
  policy = data.aws_iam_policy_document.oac_policy.json
}





# resource "aws_s3_bucket_policy" "news" {
#   depends_on = [
# 	aws_s3_bucket_public_access_block.news,
# 	aws_s3_bucket_ownership_controls.news,
#   ]

#   bucket = "${aws_s3_bucket.news.id}"

#   policy = <<POLICY
# {
#   "Version": "2012-10-17",
#   "Id": "newsBucketPolicy",
#   "Statement": [
#     {
#       "Sid":"PublicReadGetObject",
#       "Effect":"Allow",
#       "Principal": "*",
#       "Action":["s3:GetObject"],
#       "Resource":["${aws_s3_bucket.news.arn}/*"]
#     },
#     {
#       "Sid": "AllowBucketAccess",
#       "Effect": "Allow",
#       "Principal": "*",
#       "Action": "s3:ListBucket",
#       "Resource": "${aws_s3_bucket.news.arn}"
#     }
#   ]
# }
# POLICY
# }
