# Writing a model


## Getting started
In `aztk/models` create a new file with the name of your model `my_model.py`

In `aztk/models/__init__.py` add `from .my_model import MyModel`

Create a new class `MyModel` that inherit `Modle`
```python
from aztk.core.models import Model, fields

class MyModel(Model):
    """
    MyModel is an sample model

    Args:
        input1 (str): This is the first input
    """

    input1 = fields.String()

    def __validate__(self):
        pass

```

## Add validation
The fields provide basic validation automatically. A field without a default will be marked as required.

To provide model wide validation implement a `__validate__` method  and raise a `InvalidModelError` if there is any problems with the values

```python
def __validate__(self):
    if 'secret' in self.input1:
        raise InvalidModelError("Input1 contains secrets")

```

## Convert dict to model

When inheriting from `Model` it comes with a `from_dict` class method which allows to convert a dict to this class
