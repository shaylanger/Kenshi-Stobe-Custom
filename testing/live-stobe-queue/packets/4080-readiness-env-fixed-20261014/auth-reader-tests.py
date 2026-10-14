import importlib.util,json,unittest
from pathlib import Path
from types import SimpleNamespace
spec=importlib.util.spec_from_file_location('auth',Path(__file__).with_name('auth-session-read-once.py'))
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class AuthReaderTests(unittest.TestCase):
    def read(self,payload):
        return mod.read_session(lambda *a,**kw:SimpleNamespace(returncode=0,stdout=json.dumps(payload),stderr=''),lambda:({},'STOBE_DB_HOST'))
    def payload(self):
        return dict(session_present=True,status='ready',gamets=10,load_id_sha256='a'*64,generation_present=True,manager_ready_matches=True,auth_token_valid=True,auth_character_valid=True,stored_receipt_valid=True,campaign_identity_matches=True,switching_source_sha256='b'*64)
    def test_valid_bool_payload_drops_raw_auth(self):
        p=self.payload();p.update(token='SECRET_TOKEN',character_id='SECRET_CHARACTER')
        result=self.read(p)
        self.assertTrue(result['stored_receipt_valid'])
        self.assertNotIn('SECRET',json.dumps(result))
        self.assertNotIn('token',result)
    def test_missing_or_non_bool_auth_fails_closed(self):
        for change in (None,1,'true'):
            p=self.payload();p['stored_receipt_valid']=change
            self.assertEqual(self.read(p)['failure_kind'],'invalid_auth_payload')
    def test_invalid_fingerprint_fails_closed(self):
        p=self.payload();p['switching_source_sha256']='SECRET'
        self.assertEqual(self.read(p)['failure_kind'],'invalid_auth_payload')
    def test_false_auth_not_upgraded_by_ready_session(self):
        p=self.payload();p['auth_token_valid']=False;p['stored_receipt_valid']=False
        self.assertFalse(self.read(p)['stored_receipt_valid'])
if __name__=='__main__':unittest.main(verbosity=2)
