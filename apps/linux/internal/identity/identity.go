// Package identity owns this sender's long-term P-256 key, its self-signed
// certificate, and the install ID that names it on the wire.
//
// The files are the same ones the earlier implementation wrote
// (identity.json, identity.key PKCS#8 PEM, identity.crt PEM), so an existing
// pairing keeps working after upgrading: the receiver pins the certificate's
// SubjectPublicKeyInfo, which is unchanged.
package identity

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"math/big"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type Identity struct {
	InstallID string
	Key       *ecdsa.PrivateKey
	Cert      *x509.Certificate
	KeyPath   string
	CertPath  string
}

// SPKI is the pin representation of the certificate's key.
func (i *Identity) SPKI() []byte { return i.Cert.RawSubjectPublicKeyInfo }

type metadata struct {
	InstallID string `json:"installID"`
	Created   string `json:"created,omitempty"`
}

// LoadOrCreate loads the persisted identity, creating one on first run.
// A corrupt or partial identity is an error: minting a new key would look
// like an identity change to every paired receiver.
func LoadOrCreate(dir string) (*Identity, error) {
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	metaPath := filepath.Join(dir, "identity.json")
	keyPath := filepath.Join(dir, "identity.key")
	certPath := filepath.Join(dir, "identity.crt")

	metaExists := fileExists(metaPath)
	if metaExists != fileExists(keyPath) || metaExists != fileExists(certPath) {
		return nil, fmt.Errorf("identity files are incomplete in %s; refusing to mint a new identity", dir)
	}
	if metaExists {
		raw, err := os.ReadFile(metaPath)
		if err != nil {
			return nil, err
		}
		var meta metadata
		if err := json.Unmarshal(raw, &meta); err != nil || meta.InstallID == "" {
			return nil, fmt.Errorf("identity.json is unreadable")
		}
		identity, err := load(keyPath, certPath)
		if err != nil {
			return nil, err
		}
		identity.InstallID = meta.InstallID
		return identity, nil
	}

	identity, err := create(dir)
	if err != nil {
		return nil, err
	}
	raw, _ := json.MarshalIndent(metadata{
		InstallID: identity.InstallID,
		Created:   time.Now().UTC().Format("2006-01-02T15:04:05Z"),
	}, "", " ")
	if err := writePrivate(filepath.Join(dir, "identity.json"), raw); err != nil {
		return nil, err
	}
	return identity, nil
}

func load(keyPath, certPath string) (*Identity, error) {
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, err
	}
	block, _ := pem.Decode(keyPEM)
	if block == nil || block.Type != "PRIVATE KEY" {
		return nil, fmt.Errorf("identity.key is not a PKCS#8 PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, err
	}
	key, ok := parsed.(*ecdsa.PrivateKey)
	if !ok || key.Curve != elliptic.P256() {
		return nil, fmt.Errorf("identity key is not a P-256 key")
	}

	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, err
	}
	certBlock, _ := pem.Decode(certPEM)
	if certBlock == nil || certBlock.Type != "CERTIFICATE" {
		return nil, fmt.Errorf("identity.crt is not a certificate PEM")
	}
	cert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, err
	}
	public, ok := cert.PublicKey.(*ecdsa.PublicKey)
	if !ok || !public.Equal(&key.PublicKey) {
		return nil, fmt.Errorf("identity certificate does not carry the identity key")
	}
	return &Identity{Key: key, Cert: cert, KeyPath: keyPath, CertPath: certPath}, nil
}

func create(dir string) (*Identity, error) {
	installID := newUUID()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return nil, err
	}
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber:          serial,
		Subject:               pkix.Name{CommonName: installID},
		NotBefore:             now.Add(-24 * time.Hour),
		NotAfter:              now.Add(20 * 365 * 24 * time.Hour),
		BasicConstraintsValid: true,
		IsCA:                  false,
		KeyUsage:              x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return nil, err
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return nil, err
	}

	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil {
		return nil, err
	}
	keyPath := filepath.Join(dir, "identity.key")
	certPath := filepath.Join(dir, "identity.crt")
	if err := writePrivate(keyPath, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: keyDER})); err != nil {
		return nil, err
	}
	if err := os.WriteFile(certPath, pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der}), 0o644); err != nil {
		return nil, err
	}
	return &Identity{
		InstallID: installID,
		Key:       key,
		Cert:      cert,
		KeyPath:   keyPath,
		CertPath:  certPath,
	}, nil
}

func writePrivate(path string, data []byte) error {
	temporary := path + ".tmp"
	if err := os.WriteFile(temporary, data, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

func fileExists(path string) bool {
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func newUUID() string {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return strings.ToUpper(fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16]))
}
