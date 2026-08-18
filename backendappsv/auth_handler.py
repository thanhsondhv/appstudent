import base64
import hashlib
import hmac

class AspNetSigAuth:
    @staticmethod
    def verify_password_v3(hashed_password: str, provided_password: str) -> bool:
        try:
            decoded = base64.b64decode(hashed_password)
            if decoded[0] != 1: return False # Version 3 check
            
            salt = decoded[13:29] # 16 bytes salt
            stored_sub_key = decoded[29:61] # 32 bytes hash

            generated_sub_key = hashlib.pbkdf2_hmac(
                'sha256', 
                provided_password.encode('utf-8'), 
                salt, 
                10000, 
                dklen=32
            )
            return hmac.compare_digest(generated_sub_key, stored_sub_key)
        except Exception:
            return False