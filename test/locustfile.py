from locust import HttpUser, task, between


class APIUser(HttpUser):
    wait_time = between(1, 10)


    @task
    def generate_request(self):
        payload = {
            "model": "llama3.2",
            "prompt": "Why is the sky blue? use 10 words only",
            "stream": False
        }

        headers = {"Content-Type": "application/json"}
        self.client.post("/api/generate", json=payload, headers=headers)