.PHONY: deploy delete

deploy:
	sam deploy --guided

delete:
	sam delete
