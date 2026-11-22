"""UDP ağ bozucu: istemci ile sunucu arasına gecikme, titreşim ve paket kaybı koyar.

Gerçek internette oynamayı aynı bilgisayarda taklit eder:
  host   : normal (port 7777)
  bozucu : python tests/netsim.py --listen 7778 --target 7777 --latency 60 --jitter 20 --loss 3
  istemci: `-- join ... port=7778` ile bozucuya bağlanır

--latency: her yönde sabit gecikme (ms). Gidiş-dönüş (ping) yaklaşık 2 katıdır.
--jitter : gecikmeye eklenen rastgele +/- ms (paketler sırası bozulabilir, UDP gibi).
--loss   : paket kaybı yüzdesi (her yönde).
--seconds: bu süre sonra kendiliğinden çıkar.
"""
import argparse
import heapq
import itertools
import random
import socket
import threading
import time


def main() -> None:
	ap = argparse.ArgumentParser()
	ap.add_argument("--listen", type=int, default=7778)
	ap.add_argument("--target", type=int, default=7777)
	ap.add_argument("--latency", type=float, default=60.0)
	ap.add_argument("--jitter", type=float, default=20.0)
	ap.add_argument("--loss", type=float, default=3.0)
	ap.add_argument("--seconds", type=float, default=120.0)
	a = ap.parse_args()

	front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
	front.bind(("127.0.0.1", a.listen))
	front.settimeout(0.2)
	_no_connreset(front)

	upstreams = {}  # istemci adresi -> sunucuya giden soket
	heap = []  # (gönderim zamanı, sıra, soket, veri, hedef adres)
	lock = threading.Lock()
	seq = itertools.count()
	stats = {"in": 0, "dropped": 0}
	stop = threading.Event()

	def schedule(sock, data, addr):
		stats["in"] += 1
		if random.random() * 100.0 < a.loss:
			stats["dropped"] += 1
			return
		delay = max(0.0, (a.latency + random.uniform(-a.jitter, a.jitter)) / 1000.0)
		with lock:
			heapq.heappush(heap, (time.perf_counter() + delay, next(seq), sock, data, addr))

	def sender():
		while not stop.is_set():
			item = None
			with lock:
				if heap and heap[0][0] <= time.perf_counter():
					item = heapq.heappop(heap)
			if item is None:
				time.sleep(0.0005)
				continue
			_, _, sock, data, addr = item
			try:
				sock.sendto(data, addr)
			except OSError:
				pass

	def reader(up, client_addr):
		up.settimeout(0.2)
		while not stop.is_set():
			try:
				data, _ = up.recvfrom(65535)
			except socket.timeout:
				continue
			except OSError:
				continue
			schedule(front, data, client_addr)

	threading.Thread(target=sender, daemon=True).start()
	end = time.time() + a.seconds
	print(f"[netsim] {a.listen} -> {a.target}  gecikme={a.latency}ms titresim=+/-{a.jitter}ms kayip=%{a.loss}", flush=True)
	while time.time() < end:
		try:
			data, addr = front.recvfrom(65535)
		except socket.timeout:
			continue
		except OSError:
			continue
		up = upstreams.get(addr)
		if up is None:
			up = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
			up.bind(("127.0.0.1", 0))
			_no_connreset(up)
			upstreams[addr] = up
			threading.Thread(target=reader, args=(up, addr), daemon=True).start()
		schedule(up, data, ("127.0.0.1", a.target))
	stop.set()
	print(f"[netsim] bitti: {stats['in']} paket, {stats['dropped']} düştü", flush=True)


def _no_connreset(sock: socket.socket) -> None:
	"""Windows: karşı uç kapalıyken gelen ICMP hatası recvfrom'u bozmasın."""
	try:
		sock.ioctl(socket.SIO_UDP_CONNRESET, False)  # type: ignore[attr-defined]
	except (AttributeError, OSError, ValueError):
		pass


if __name__ == "__main__":
	main()
