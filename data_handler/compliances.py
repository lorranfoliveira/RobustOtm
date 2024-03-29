from __future__ import annotations

from .base_data import BaseData
from math import pi

class Compliance(BaseData):
    _KEY = ''

    @property
    def key(self) -> str:
        return self._KEY

    def parameters(self) -> dict:
        pass

    @classmethod
    def read_dict(cls, dct: dict) -> type(Compliance):
        pass

    def to_dict(self):
        return {'key': self.key,
                "parameters": self.parameters()}


class ComplianceNominal(Compliance):
    _KEY = 'nominal'

    @classmethod
    def read_dict(cls, dct: dict) -> type(Compliance):
        return cls()

    def to_dict(self):
        return {'key': self.key}


class ComplianceMu(Compliance):
    _KEY = 'mu'

    def __init__(self, beta: float = 0.1):
        super().__init__()
        self.beta = beta

    @classmethod
    def read_dict(cls, dct: dict) -> type(Compliance):
        return cls(beta=dct['parameters']['beta'])

    def parameters(self) -> dict:
        return {'beta': self.beta}


class CompliancePNorm(Compliance):
    _KEY = 'p_norm'

    def __init__(self, p: float = 20):
        super().__init__()
        self.p = p

    @classmethod
    def read_dict(cls, dct: dict) -> type(Compliance):
        return cls(p=dct['parameters']['p'])

    def parameters(self) -> dict:
        return {'p': self.p}
    

class ComplianceSmoothTheta(Compliance):
    _KEY = 'smooth_theta'

    def __init__(self, theta_r: float = pi/2, beta: float = 0.1):
        super().__init__()
        self.beta = beta
        self.theta_r = theta_r

    @classmethod
    def read_dict(cls, dct: dict) -> type(Compliance):
        return cls(theta_r=dct['parameters']['theta_r'],
                   beta=dct['parameters']['beta'])

    def parameters(self) -> dict:
        return {'theta_r': self.theta_r,
                'beta': self.beta}
